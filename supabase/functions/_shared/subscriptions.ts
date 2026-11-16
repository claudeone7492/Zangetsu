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
 * Builds a Korapay reference for a subscription charge. Korapay rejects
 * references longer than 50 characters, so the UUID is truncated.
 */
export function buildSubscriptionReference(planKey: string, kind: "sub" | "trial" | "renew"): string {
  const slug = planKey.replace(/[^a-z0-9]/gi, "").slice(0, 10);
  const id = crypto.randomUUID().replace(/-/g, "").slice(0, 24);
  return `sx_${kind}_${slug}_${id}`;
}

/** Customer email for Korapay. Sessions are anonymous, so synthesise one. */
export function sessionEmail(sessionId: string): string {
  return `${sessionId}@users.sophie.app`;
}
