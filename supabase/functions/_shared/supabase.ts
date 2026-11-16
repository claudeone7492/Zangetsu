// Service-role Supabase client for edge functions.
//
// Edge functions run with the service-role key, which bypasses RLS. They must
// never expose that key to a caller — every response is shaped by hand.

import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

let client: SupabaseClient | null = null;

export function adminClient(): SupabaseClient {
  if (client) return client;
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set");
  }
  client = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return client;
}

/** Platform fee in cents, mirroring backend/src/payments.ts. */
export function platformFee(amountCents: number, feePercentage = 20): number {
  return Math.round((amountCents * feePercentage) / 100);
}
