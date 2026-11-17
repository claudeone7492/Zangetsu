// POST /functions/v1/stream-subscribe
// Starts a Zangetsu stream subscription and returns a Korapay checkout URL.
//
// Body: { fingerprint, planKey, promoCode? }
//
// Identity is the device fingerprint, not a login. The fingerprint is resolved
// to its device session server-side, so a caller can only ever subscribe the
// device it is running on.
//
// A promo that covers the full price activates immediately with no charge.
// Otherwise a pending subscription + payment are written and a Korapay
// checkout URL is returned; the korapay-webhook settles it when the charge
// succeeds.

import { adminClient, platformFee } from "../_shared/supabase.ts";
import { initializeCharge, korapayMode } from "../_shared/korapay.ts";
import {
  buildSubscriptionReference,
  loadLaunchDiscountPct,
  loadPlan,
  priceStreamPlan,
  sessionEmail,
} from "../_shared/subscriptions.ts";
import { handleOptions, json } from "../_shared/cors.ts";

interface PromoRow {
  code: string;
  percent_off: number | null;
  kind: string | null;
  max_uses: number | null;
  used_count: number | null;
  expires_at: string | null;
  active: boolean;
}

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: { fingerprint?: string; planKey?: string; promoCode?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const fingerprint = body.fingerprint;
  if (!fingerprint || typeof fingerprint !== "string" || fingerprint.length < 8) {
    return json({ error: "invalid_body", detail: "fingerprint required" }, 400);
  }
  if (!body.planKey) return json({ error: "invalid_body", detail: "planKey required" }, 400);

  const db = adminClient();

  const { data: session } = await db.rpc("get_subscription_session", {
    p_fingerprint: fingerprint,
  });
  if (!session) return json({ error: "device_not_registered" }, 404);

  const { data: profile } = await db
    .from("user_profiles")
    .select("is_banned, display_name")
    .eq("session_id", session)
    .maybeSingle();
  if (profile?.is_banned) return json({ error: "account_banned" }, 403);

  const plan = await loadPlan(db, body.planKey);
  if (!plan) return json({ error: "unknown_plan" }, 404);

  // Resolve the promo server-side; the client's copy is only a preview.
  let percentOff = 0;
  let promoCode: string | null = null;
  if (body.promoCode) {
    const { data: promo } = await db
      .from("promo_codes")
      .select("code, percent_off, kind, max_uses, used_count, expires_at, active")
      .eq("code", body.promoCode)
      .eq("valid_for", "stream")
      .maybeSingle();
    const p = promo as PromoRow | null;
    const usable = p && p.active &&
      (!p.expires_at || new Date(p.expires_at) > new Date()) &&
      (p.max_uses === null || (p.used_count ?? 0) < p.max_uses);
    if (usable) {
      percentOff = p.kind === "free" ? 100 : (p.percent_off ?? 0);
      promoCode = p.code;
    }
  }

  const launchDiscountPct = await loadLaunchDiscountPct(db);
  const pricing = priceStreamPlan(
    plan.price_usd_cents,
    launchDiscountPct,
    percentOff,
  );
  const listCents = pricing.listCents;
  const amountCents = pricing.amountCents;
  const reference = buildSubscriptionReference(plan.key, "sub");

  // A fully-discounted plan needs no charge: grant it outright and record the
  // redemption so the code's usage counter still moves.
  if (amountCents === 0) {
    const { error: activateError } = await db.rpc("activate_stream_subscription", {
      p_session: session,
      p_plan_key: plan.key,
      p_reference: reference,
    });
    if (activateError) {
      return json({ error: "activation_failed", detail: activateError.message }, 500);
    }
    if (promoCode) {
      await db.rpc("redeem_promo", {
        p_code: promoCode,
        p_fingerprint: fingerprint,
        p_plan: plan.key,
        p_before: listCents,
        p_after: 0,
      });
    }
    return json({
      ok: true,
      free: true,
      reference,
      planKey: plan.key,
      entitlement: plan.entitlement,
      listUsdCents: listCents,
      offerUsdCents: pricing.offerCents,
      amountUsdCents: 0,
      launchDiscountPct: pricing.launchDiscountPct,
      percentOff,
      checkoutUrl: null,
      status: "active",
    });
  }

  const fee = platformFee(amountCents);

  // A pending subscription row is what the webhook settles. Re-subscribing the
  // same plan reuses the row rather than stacking a second one.
  const { data: sub, error: subError } = await db
    .from("subscriptions")
    .upsert({
      subscriber_session_id: session,
      plan_key: plan.key,
      entitlement: plan.entitlement,
      status: "pending",
      auto_renew: true,
      current_period_start: new Date().toISOString(),
      current_period_end: new Date(Date.now() + plan.period_days * 86400_000).toISOString(),
      grace_until: new Date(Date.now() + (plan.period_days + plan.grace_days) * 86400_000).toISOString(),
      korapay_reference: reference,
    }, { onConflict: "subscriber_session_id,plan_key" })
    .select("id")
    .single();
  if (subError) {
    return json({ error: "subscription_upsert_failed", detail: subError.message }, 500);
  }

  const { data: payment, error: payError } = await db
    .from("payments")
    .insert({
      payer_session_id: session,
      receiver_session_id: session,
      product_type: plan.product_type,
      amount: amountCents,
      korapay_reference: reference,
      platform_fee: fee,
      promo_code_used: promoCode,
      status: "pending",
      subscription_id: sub.id,
    })
    .select("id")
    .single();
  if (payError) {
    return json({ error: "payment_insert_failed", detail: payError.message }, 500);
  }

  const charge = await initializeCharge({
    amountCents,
    reference,
    customerName: profile?.display_name ?? "Zangetsu User",
    customerEmail: sessionEmail(session),
    notificationUrl: `${Deno.env.get("SUPABASE_URL")}/functions/v1/korapay-webhook`,
  });

  if (!charge.ok) {
    await db.from("payments").update({ status: "failed" }).eq("id", payment.id);
    await db.from("subscriptions").update({ status: "lapsed" }).eq("id", sub.id);
    return json({ error: "korapay_init_failed", detail: charge.error, reference }, 502);
  }

  return json({
    ok: true,
    free: false,
    subscriptionId: sub.id,
    paymentId: payment.id,
    reference,
    planKey: plan.key,
    entitlement: plan.entitlement,
    listUsdCents: listCents,
    offerUsdCents: pricing.offerCents,
    amountUsdCents: amountCents,
    launchDiscountPct: pricing.launchDiscountPct,
    percentOff,
    platformFeeUsdCents: fee,
    checkoutUrl: charge.checkoutUrl ?? null,
    status: "pending",
    mode: korapayMode(),
  });
});
