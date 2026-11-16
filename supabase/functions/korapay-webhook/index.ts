// POST /functions/v1/korapay-webhook
// Korapay calls this when a charge settles, renews, fails or is refunded.
//
// The raw body is verified against the x-korapay-signature HMAC before anything
// is trusted. Every delivery is recorded in `payment_events` by (reference,
// event) so a replayed webhook is a no-op rather than a double credit.
//
// Settles both the Sophie products (vip_unlock, tips, sessions) and the
// Zangetsu stream subscriptions (subscription_stream).

import { adminClient } from "../_shared/supabase.ts";
import { verifyWebhook } from "../_shared/korapay.ts";
import { handleOptions, json } from "../_shared/cors.ts";

interface KorapayEvent {
  event?: string;
  data?: {
    reference?: string;
    status?: string;
    amount?: number;
    currency?: string;
    payment_reference?: string;
  };
}

const SUBSCRIPTION_PRODUCTS = new Set([
  "subscription_vip",
  "subscription_creator",
  "subscription_premium",
  "subscription_stream",
]);

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const rawBody = await req.text();
  const signature = req.headers.get("x-korapay-signature");

  if (!(await verifyWebhook(rawBody, signature))) {
    return json({ error: "invalid_signature" }, 401);
  }

  let event: KorapayEvent;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const reference = event.data?.reference;
  const eventType = event.event ?? "unknown";
  if (!reference) return json({ error: "missing_reference" }, 400);

  const db = adminClient();

  // The payment must exist before anything is recorded. Logging an unknown
  // reference would poison the idempotency table, so a later real delivery for
  // the same reference would be dropped as a duplicate.
  const { data: payment } = await db
    .from("payments")
    .select("id, payer_session_id, receiver_session_id, product_type, amount, status, subscription_id")
    .eq("korapay_reference", reference)
    .maybeSingle();

  if (!payment) return json({ error: "unknown_reference" }, 404);

  // Idempotency by (reference, event). A unique-violation means we have seen
  // this exact delivery, so stop here.
  const { error: logError } = await db
    .from("payment_events")
    .insert({ reference, event_type: eventType, payload: event.data ?? {} });
  if (logError?.code === "23505") {
    return json({ received: true, alreadyProcessed: true });
  }

  const succeeded = event.event === "charge.success" && event.data?.status === "success";
  const refunded = event.event === "charge.refunded" || event.data?.status === "refunded";
  const isSubscription = SUBSCRIPTION_PRODUCTS.has(payment.product_type);

  // A refund or chargeback revokes access immediately, subscription or not.
  if (refunded) {
    await db.from("payments").update({ status: "refunded" }).eq("id", payment.id);
    if (payment.subscription_id) {
      await db.rpc("revoke_subscription", { p_subscription_id: payment.subscription_id });
    }
    return json({ received: true, status: "refunded", product: payment.product_type });
  }

  if (!succeeded) {
    // A failed renewal does not revoke anything here: the subscription moves to
    // grace on its own clock, and lapses only when grace runs out.
    await db.from("payments").update({ status: "failed" }).eq("id", payment.id);
    return json({ received: true, status: "failed" });
  }

  // Already settled: nothing to do.
  if (payment.status === "completed") {
    return json({ received: true, alreadyProcessed: true });
  }

  await db
    .from("payments")
    .update({ status: "completed", completed_at: new Date().toISOString() })
    .eq("id", payment.id);

  if (isSubscription) {
    await settleSubscription(db, payment, reference);
    return json({ received: true, status: "completed", product: payment.product_type });
  }

  await settleOneOff(db, payment);
  return json({ received: true, status: "completed", product: payment.product_type });
});

/**
 * Settles a subscription charge. The first successful charge starts (or
 * restarts) the period; a later charge for the same subscription renews it.
 */
async function settleSubscription(
  db: ReturnType<typeof adminClient>,
  payment: {
    subscription_id: string | null;
    payer_session_id: string;
    product_type: string;
    amount: number;
  },
  reference: string,
) {
  if (!payment.subscription_id) return;

  const { data: sub } = await db
    .from("subscriptions")
    .select("id, status, plan_key, current_period_end")
    .eq("id", payment.subscription_id)
    .maybeSingle();
  if (!sub) return;

  // A stream plan is paid for outright: activate exactly period_days with no
  // trial days (start_subscription_period would add them again). A renewal of
  // an already-active stream period is the same call.
  if (payment.product_type === "subscription_stream") {
    await db.rpc("activate_stream_subscription", {
      p_session: payment.payer_session_id,
      p_plan_key: sub.plan_key,
      p_reference: reference,
    });
    await db.from("notification_log").insert({
      session_id: payment.payer_session_id,
      kind: "transactional",
      title: "Subscription active",
      body: "Your Zangetsu subscription is active and renews automatically.",
    });
    return;
  }

  // `pending` means the very first charge has not landed yet; anything else is
  // a renewal of an existing period.
  if (sub.status === "pending") {
    await db.rpc("start_subscription_period", {
      p_subscriber: payment.payer_session_id,
      p_plan_key: sub.plan_key,
      p_reference: reference,
    });
  } else {
    await db.rpc("renew_subscription", { p_subscription_id: sub.id, p_reference: reference });
  }

  await db.from("notification_log").insert({
    session_id: payment.payer_session_id,
    kind: "transactional",
    title: "Subscription active",
    body: "Your Sophie subscription is active and renews automatically.",
  });
}

/** Settles a one-off purchase: VIP unlock, tip, session, contact reveal. */
async function settleOneOff(
  db: ReturnType<typeof adminClient>,
  payment: {
    id: string;
    payer_session_id: string;
    receiver_session_id: string;
    product_type: string;
    amount: number;
  },
) {
  const payer = payment.payer_session_id;

  switch (payment.product_type) {
    case "vip_unlock": {
      const { data: p } = await db
        .from("user_profiles")
        .select("vip_bypass_used")
        .eq("session_id", payer)
        .maybeSingle();
      await db
        .from("user_profiles")
        .update({
          is_vip: true,
          vip_unlocked_at: new Date().toISOString(),
          vip_paid_amount: payment.amount,
          vip_bypass_used: p?.vip_bypass_used ?? false,
        })
        .eq("session_id", payer);
      // A lifetime VIP unlock is recorded as a non-expiring entitlement too.
      await db.from("entitlements").upsert(
        {
          subscriber_session_id: payer,
          entitlement: "vip",
          active: true,
          source: "purchase",
          expires_at: null,
          updated_at: new Date().toISOString(),
        },
        { onConflict: "subscriber_session_id,entitlement" },
      );
      break;
    }
    case "tip": {
      await db.rpc("award_xp", { p_session_id: payer, p_action: "tip_sent" });
      await db.rpc("award_xp", {
        p_session_id: payment.receiver_session_id,
        p_action: "tip_received",
      });
      break;
    }
    case "private_session":
      await db.rpc("award_xp", { p_session_id: payer, p_action: "private_session" });
      break;
    case "group_session":
      await db.rpc("award_xp", { p_session_id: payer, p_action: "group_session" });
      break;
    case "contact_reveal": {
      // Records the unlock so the buyer may see the creator's contact details.
      // The unique pair makes a repeat purchase a no-op.
      await db.from("contact_reveals").upsert(
        {
          subscriber_session_id: payer,
          creator_session_id: payment.receiver_session_id,
          payment_id: payment.id,
        },
        { onConflict: "subscriber_session_id,creator_session_id", ignoreDuplicates: true },
      );
      break;
    }
  }

  if (payment.product_type === "vip_unlock") {
    await db.from("notification_log").insert({
      session_id: payer,
      kind: "transactional",
      title: "VIP unlocked",
      body: "Your Sophie VIP access is now active.",
    });
  }
}
