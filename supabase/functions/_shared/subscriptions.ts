// Subscription helpers shared by the subscription edge functions.
//
// Plans live in the database so they can change without a deploy. The lifecycle
// itself is enforced in SQL (supabase/migrations/0006_trial_and_entitlement.sql);
// these helpers only read plans and build references.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

export interface PlanRow {
  key: string;
  product_type: string;
  entitlement: string;
  label: string;
  price_usd_cents: number;
  period_days: number;
  trial_days: number;
  grace_days: number;
  features: unknown;
}

export async function loadPlan(
  db: SupabaseClient,
  planKey: string,
): Promise<PlanRow | null> {
  const { data } = await db
    .from("subscription_plans")
    .select("key, product_type, entitlement, label, price_usd_cents, period_days, trial_days, grace_days, features")
    .eq("key", planKey)
    .eq("active", true)
    .maybeSingle();
  return (data as PlanRow) ?? null;
}

/**
 * The admin-managed launch discount, as a whole percentage. Defaults to 0 so a
 * missing row (or a failed read) never invents a discount the charge won't
 * honour — quoting a higher price than is charged is the safe direction.
 */
export async function loadLaunchDiscountPct(db: SupabaseClient): Promise<number> {
  const { data } = await db
    .from("app_config")
    .select("stream_launch_discount_pct")
    .limit(1)
    .maybeSingle();
  const raw = (data as { stream_launch_discount_pct?: number } | null)
    ?.stream_launch_discount_pct;
  if (typeof raw !== "number" || !Number.isFinite(raw)) return 0;
  return clampPct(raw);
}

function clampPct(value: number): number {
  return Math.min(100, Math.max(0, Math.round(value)));
}

export interface StreamPricing {
  listCents: number;
  /** List price after the launch discount, before any promo. */
  offerCents: number;
  /** What Korapay is asked to charge. */
  amountCents: number;
  launchDiscountPct: number;
  promoPercentOff: number;
}

/**
 * Prices a stream plan the way the paywall quotes it: the launch discount comes
 * off the list price, then the promo comes off that. The rounding matches the
 * client's (`offerCents`, then `totalCents`) so the number on the button is the
 * number that gets charged.
 */
export function priceStreamPlan(
  listCents: number,
  launchDiscountPct: number,
  promoPercentOff: number,
): StreamPricing {
  const launch = clampPct(launchDiscountPct);
  const promo = clampPct(promoPercentOff);
  const offerCents = Math.round((listCents * (100 - launch)) / 100);
  const amountCents = Math.max(
    0,
    Math.round((offerCents * (100 - promo)) / 100),
  );
  return {
    listCents,
    offerCents,
    amountCents,
    launchDiscountPct: launch,
    promoPercentOff: promo,
  };
}

/**
 * Builds a Korapay reference for a subscription charge. Korapay rejects
 * references longer than 50 characters, so the UUID is truncated.
 */
export function buildSubscriptionReference(planKey: string, kind: "sub" | "trial" | "renew"): string {
  const slug = planKey.replace(/[^a-z0-9]/gi, "").slice(0, 10);
  const id = crypto.randomUUID().replace(/-/g, "").slice(0, 24);
  return `sx_${kind}_${slug}_${id}`;
}

/** Merchant contact used for every stream charge. Sessions are anonymous, so
 * Kora's required customer.email is the merchant address, not the viewer's.
 * The payment reference remains the link back to the initiating device. */
export const MERCHANT_EMAIL = "edgesenterprise@outlook.com";

export function merchantEmail(): string {
  return Deno.env.get("KORAPAY_MERCHANT_EMAIL")?.trim() || MERCHANT_EMAIL;
}
