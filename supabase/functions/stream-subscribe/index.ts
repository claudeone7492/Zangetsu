// POST /functions/v1/stream-subscribe
// Starts a Zangetsu stream subscription and returns a hosted checkout URL.
//
// Body: { fingerprint, planKey, promoCode?, country? }
//
// Identity is the device fingerprint, not a login. The fingerprint is resolved
// to its device session server-side, so a caller can only ever subscribe the
// device it is running on.
//
// A promo that covers the full price activates immediately with no charge.
// Otherwise a pending subscription + payment are written and a checkout URL is
// returned. The gateway is chosen server-side from the caller's country: Korapay
// where its live account has the local currency, Flutterwave everywhere else.
// The matching webhook (korapay-webhook / flutterwave-webhook) settles it when
// the charge succeeds.

import { adminClient, platformFee } from "../_shared/supabase.ts";
import {
  initializeCharge as initializeKorapayCharge,
  korapayConfigured,
  korapayMode,
} from "../_shared/korapay.ts";
import {
  type ChargeResult,
  flutterwaveConfigured,
  flutterwaveMode,
  initializeCharge as initializeFlutterwaveCharge,
  verifyTransactionByReference,
} from "../_shared/flutterwave.ts";
import {
  resolvePaymentCountry,
  resolvePaymentReturnUrl,
} from "../_shared/payment_routing.ts";
import { listPriceCents, planCharge } from "../_shared/charge_currency.ts";
import {
  buildSubscriptionReference,
  loadLaunchDiscountPct,
  loadPlan,
  merchantEmail,
  priceStreamPlan,
} from "../_shared/subscriptions.ts";
import {
  type PaymentRow,
  settleSuccessfulCharge,
} from "../_shared/settle.ts";
import { handleOptions, json } from "../_shared/cors.ts";

interface PromoRow {
  code: string;
  percent_off: number | null;
  kind: string | null;
  already_used: boolean;
  usable: boolean;
}

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: {
    action?: string;
    fingerprint?: string;
    planKey?: string;
    promoCode?: string;
    country?: string;
    returnUrl?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const fingerprint = body.fingerprint;
  if (
    !fingerprint || typeof fingerprint !== "string" || fingerprint.length < 8
  ) {
    return json({ error: "invalid_body", detail: "fingerprint required" }, 400);
  }
  const db = adminClient();

  // Confirmation without a webhook: the client polls with its fingerprint and
  // the server asks Flutterwave, with the secret key, whether the pending
  // charge was paid. Nothing is credited unless the reference and amount match.
  if (body.action === "verify") {
    return await confirmPendingFlutterwavePayment(db, fingerprint);
  }

  if (!body.planKey) {
    return json({ error: "invalid_body", detail: "planKey required" }, 400);
  }

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

  // The charge currency follows the same country the rail is picked from, so
  // the list price is chosen here rather than at plan load: local African
  // rails are $1, everything else the overseas tier.
  const country = await resolvePaymentCountry(req, body.country);

  // Resolve the promo server-side; the client's copy is only a preview. The
  // RPC is the same one the app calls, so both sides agree on the canonical
  // code, its discount, and whether this device has already consumed it.
  let percentOff = 0;
  let promoCode: string | null = null;
  if (body.promoCode) {
    const { data: rows, error: promoError } = await db.rpc("resolve_promo", {
      p_code: body.promoCode,
      p_plan: plan.key,
      p_fingerprint: fingerprint,
    });
    if (promoError) {
      return json(
        { error: "promo_lookup_failed", detail: promoError.message },
        500,
      );
    }
    const p = ((rows as PromoRow[] | null) ?? [])[0];
    if (!p) return json({ error: "promo_unavailable" }, 409);
    if (p.already_used) return json({ error: "promo_already_used" }, 409);
    if (!p.usable) return json({ error: "promo_unavailable" }, 409);

    percentOff = p.kind === "free" ? 100 : (p.percent_off ?? 0);
    promoCode = p.code;
  }

  const launchDiscountPct = await loadLaunchDiscountPct(db);
  const pricing = priceStreamPlan(
    listPriceCents(plan, country),
    launchDiscountPct,
    percentOff,
  );
  const listCents = pricing.listCents;
  const amountCents = pricing.amountCents;
  const reference = buildSubscriptionReference(plan.key, "sub");

  // A fully-discounted plan needs no charge. Consume the code first so two
  // simultaneous requests cannot both activate a free month; the redemption
  // row is what makes the code one-time-per-device.
  if (amountCents === 0) {
    if (promoCode) {
      const { data: redeemed, error: redeemError } = await db.rpc(
        "redeem_promo",
        {
          p_code: promoCode,
          p_fingerprint: fingerprint,
          p_plan: plan.key,
          p_before: listCents,
          p_after: 0,
        },
      );
      if (redeemError) {
        return json({
          error: "promo_redeem_failed",
          detail: redeemError.message,
        }, 500);
      }
      if (redeemed === null) {
        return json({ error: "promo_already_used" }, 409);
      }
    }

    const { error: activateError } = await db.rpc(
      "activate_stream_subscription",
      {
        p_session: session,
        p_plan_key: plan.key,
        p_reference: reference,
      },
    );
    if (activateError) {
      return json(
        { error: "activation_failed", detail: activateError.message },
        500,
      );
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

  // Gateway and currency selection are server-side: trusted edge country
  // header, then the caller's IP, then the client's locale hint. Local African
  // rails charge in their own currency; everything else is charged in USD by
  // Flutterwave.
  const chargePlan = await planCharge(amountCents, country, {
    korapayConfigured: korapayConfigured(),
    flutterwaveConfigured: flutterwaveConfigured(),
  });
  if (chargePlan.error) {
    return json({
      error: chargePlan.error,
      detail: chargePlan.detail,
      currency: chargePlan.currency,
      amount: chargePlan.amountMajor,
      amountUsdCents: amountCents,
    }, 409);
  }
  let provider = chargePlan.providers[0];

  const fee = platformFee(amountCents);
  const billingEmail = merchantEmail();

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
      current_period_end: new Date(Date.now() + plan.period_days * 86400_000)
        .toISOString(),
      grace_until: new Date(
        Date.now() + (plan.period_days + plan.grace_days) * 86400_000,
      ).toISOString(),
      korapay_reference: reference,
    }, { onConflict: "subscriber_session_id,plan_key" })
    .select("id")
    .single();
  if (subError) {
    return json({
      error: "subscription_upsert_failed",
      detail: subError.message,
    }, 500);
  }

  const { data: payment, error: payError } = await db
    .from("payments")
    .insert({
      payer_session_id: session,
      receiver_session_id: session,
      product_type: plan.product_type,
      amount: amountCents,
      charge_currency: chargePlan.currency,
      charge_amount: chargePlan.amountMajor,
      customer_email: billingEmail,
      korapay_reference: reference,
      payment_provider: provider,
      platform_fee: fee,
      promo_code_used: promoCode,
      status: "pending",
      subscription_id: sub.id,
    })
    .select("id")
    .single();
  if (payError) {
    return json(
      { error: "payment_insert_failed", detail: payError.message },
      500,
    );
  }

  const redirectUrl = resolvePaymentReturnUrl(body.returnUrl, {
    base: Deno.env.get("PAYMENT_RETURN_BASE_URL"),
    allowedHosts: Deno.env.get("PAYMENT_RETURN_ALLOWED_HOSTS"),
  });
  const customerName = profile?.display_name ?? "Zangetsu User";
  const routedProvider = provider;

  // If the preferred gateway cannot start the charge (an outage, or a rail it
  // no longer takes), try the other one with the same reference. Only one
  // checkout link reaches the user, and the webhook of the gateway that
  // produced it is the only one allowed to settle it.
  const candidates = chargePlan.providers;
  let charge: ChargeResult | null = null;
  for (const candidate of candidates) {
    charge = candidate === "korapay"
      ? await initializeKorapayCharge({
        amountMajor: chargePlan.amountMajor,
        currency: chargePlan.currency,
        reference,
        narration: "Zangetsu subscription",
        customerName,
        customerEmail: billingEmail,
        notificationUrl: `${
          Deno.env.get("SUPABASE_URL")
        }/functions/v1/korapay-webhook`,
        redirectUrl,
      })
      : await initializeFlutterwaveCharge({
        amountMajor: chargePlan.amountMajor,
        currency: chargePlan.currency,
        reference,
        narration: "Zangetsu subscription",
        customerName,
        customerEmail: billingEmail,
        redirectUrl,
      });

    if (charge.ok) {
      provider = candidate;
      break;
    }
  }

  if (!charge?.ok) {
    await db.from("payments").update({ status: "failed" }).eq("id", payment.id);
    await db.from("subscriptions").update({ status: "lapsed" }).eq(
      "id",
      sub.id,
    );
    return json({
      error: "checkout_init_failed",
      detail: charge?.error,
      reference,
      currency: chargePlan.currency,
      amount: chargePlan.amountMajor,
    }, 502);
  }

  if (provider !== routedProvider) {
    await db
      .from("payments")
      .update({ payment_provider: provider })
      .eq("id", payment.id);
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
    chargeCurrency: chargePlan.currency,
    chargeAmount: chargePlan.amountMajor,
    launchDiscountPct: pricing.launchDiscountPct,
    percentOff,
    platformFeeUsdCents: fee,
    checkoutUrl: charge.checkoutUrl ?? null,
    returnUrl: redirectUrl,
    status: "pending",
    provider,
    country,
    mode: provider === "korapay" ? korapayMode() : flutterwaveMode(),
  });
});


/**
 * Confirms a pending Flutterwave charge for [fingerprint] without a webhook.
 * Repeated polls and the webhook both settle idempotently, so a race between
 * them cannot credit twice.
 */
async function confirmPendingFlutterwavePayment(
  db: ReturnType<typeof adminClient>,
  fingerprint: string,
) {
  const { data: session } = await db.rpc("get_subscription_session", {
    p_fingerprint: fingerprint,
  });
  if (!session) return json({ error: "device_not_registered" }, 404);

  const { data: pending, error } = await db
    .from("payments")
    .select(
      "id, payer_session_id, receiver_session_id, product_type, amount, charge_currency, charge_amount, status, subscription_id, promo_code_used, payment_provider, korapay_reference",
    )
    .eq("payer_session_id", session)
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .limit(5);
  if (error) {
    return json({ error: "payment_lookup_failed", detail: error.message }, 500);
  }

  let settled = 0;
  for (const payment of (pending ?? []) as PaymentRow[]) {
    if (
      payment.payment_provider !== "flutterwave" ||
      !payment.korapay_reference
    ) {
      continue;
    }

    const verified = await verifyTransactionByReference(
      payment.korapay_reference,
    );
    if (!verified.ok || verified.status !== "successful") continue;
    if (verified.txRef && verified.txRef !== payment.korapay_reference) {
      continue;
    }
    const expectedAmount = Number(
      payment.charge_amount ?? payment.amount / 100,
    );
    const expectedCurrency = (payment.charge_currency ?? "USD").toUpperCase();
    if (verified.currency && verified.currency.toUpperCase() !== expectedCurrency) {
      continue;
    }
    if (
      verified.amountMajor != null &&
      Math.abs(verified.amountMajor - expectedAmount) > 0.01
    ) {
      continue;
    }

    await settleSuccessfulCharge(db, payment, payment.korapay_reference);
    settled++;
  }

  return json({ ok: true, settled });
}
