// Settlement shared by the Korapay and Flutterwave webhooks.
//
// Both gateways confirm the same payment row, so the lifecycle (subscription
// activation, one-off unlocks, refund revocation, event idempotency) lives here
// once. The webhook functions only translate their gateway's payload and verify
// its signature.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

export const SUBSCRIPTION_PRODUCTS = new Set([
  "subscription_vip",
  "subscription_creator",
  "subscription_premium",
  "subscription_stream",
]);

export interface PaymentRow {
  id: string;
  payer_session_id: string;
  receiver_session_id: string;
  product_type: string;
  amount: number;
  status: string;
  subscription_id: string | null;
  promo_code_used: string | null;
  payment_provider?: string | null;
  korapay_reference?: string | null;
}

/**
 * Records a webhook delivery by (reference, event). Returns "duplicate" when a
 * unique violation proves this exact delivery was already handled, which makes
 * a replay a no-op rather than a double credit.
 */
export async function recordPaymentEvent(
  db: SupabaseClient,
  reference: string,
  eventType: string,
  payload: unknown,
): Promise<"new" | "duplicate"> {
  const { error } = await db
    .from("payment_events")
    .insert({ reference, event_type: eventType, payload: payload ?? {} });
  return error?.code === "23505" ? "duplicate" : "new";
}

export async function markPaymentFailed(
  db: SupabaseClient,
  payment: PaymentRow,
): Promise<void> {
  await db.from("payments").update({ status: "failed" }).eq("id", payment.id);
}

/** A refund or chargeback revokes access immediately, subscription or not. */
export async function revokePayment(
  db: SupabaseClient,
  payment: PaymentRow,
): Promise<void> {
  await db.from("payments").update({ status: "refunded" }).eq("id", payment.id);
  if (payment.subscription_id) {
    await db.rpc("revoke_subscription", {
      p_subscription_id: payment.subscription_id,
    });
  }
}

/** Settles a successful charge: subscriptions first, then one-off products. */
export async function settleSuccessfulCharge(
  db: SupabaseClient,
  payment: PaymentRow,
  reference: string,
): Promise<void> {
  if (payment.status === "completed") return;

  await db
    .from("payments")
    .update({ status: "completed", completed_at: new Date().toISOString() })
    .eq("id", payment.id);

  if (SUBSCRIPTION_PRODUCTS.has(payment.product_type)) {
    await settleSubscription(db, payment, reference);
    return;
  }

  await settleOneOff(db, payment);
}

/**
 * Records a paid promo against the device that started the checkout. The
 * redemption is idempotent, so a replay or a second settled charge cannot
 * create a second use. This runs only after the charge succeeded, which keeps
 * an abandoned checkout from consuming the code.
 */
async function recordPromoUse(
  db: SupabaseClient,
  payment: PaymentRow,
  planKey: string,
) {
  if (!payment.promo_code_used) return;

  const { data: device } = await db
    .from("devices")
    .select("fingerprint")
    .eq("session_id", payment.payer_session_id)
    .limit(1)
    .maybeSingle();
  if (!device?.fingerprint) return;

  await db.rpc("redeem_promo", {
    p_code: payment.promo_code_used,
    p_fingerprint: device.fingerprint,
    p_plan: planKey,
    p_before: null,
    p_after: payment.amount,
  });
}

/**
 * Settles a subscription charge. The first successful charge starts (or
 * restarts) the period; a later charge for the same subscription renews it.
 */
async function settleSubscription(
  db: SupabaseClient,
  payment: PaymentRow,
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
    await recordPromoUse(db, payment, sub.plan_key);
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
    await db.rpc("renew_subscription", {
      p_subscription_id: sub.id,
      p_reference: reference,
    });
  }

  await db.from("notification_log").insert({
    session_id: payment.payer_session_id,
    kind: "transactional",
    title: "Subscription active",
    body: "Your Sophie subscription is active and renews automatically.",
  });
}

/** Settles a one-off purchase: VIP unlock, tip, session, contact reveal. */
async function settleOneOff(db: SupabaseClient, payment: PaymentRow) {
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
      await db.rpc("award_xp", {
        p_session_id: payer,
        p_action: "private_session",
      });
      break;
    case "group_session":
      await db.rpc("award_xp", {
        p_session_id: payer,
        p_action: "group_session",
      });
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
        {
          onConflict: "subscriber_session_id,creator_session_id",
          ignoreDuplicates: true,
        },
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
