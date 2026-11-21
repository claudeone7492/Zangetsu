// Korapay client. LIVE keys are the default; KORAPAY_MODE=test opts a
// deployment back onto the sandbox keys.
//
// Production is the safe default: an unset (or misspelled) KORAPAY_MODE must
// never silently drop a live deployment onto the test keys, where charges look
// like they succeed but no money is ever captured. So only an explicit "test"
// (or "sandbox") selects the test keys; anything else unrecognised throws
// rather than quietly resolving to either.
//
// Only the secret key is used server-side. The public key is echoed to the
// client so it can render the checkout, never the secret.

import { hmacSha256Hex, safeEqual } from "./cors.ts";

const DEFAULT_BASE = "https://api.korapay.com/merchant/api/v1";

/** Pure mode resolution, split out from the env read so it is testable. */
export function resolveKorapayMode(raw: string | undefined): "test" | "live" {
  const value = (raw ?? "").trim().toLowerCase();
  if (value === "test" || value === "sandbox") return "test";
  if (value === "" || value === "live") return "live";
  throw new Error(`KORAPAY_MODE must be "live" or "test" (got "${raw}")`);
}

export function korapayMode(): "test" | "live" {
  return resolveKorapayMode(Deno.env.get("KORAPAY_MODE"));
}

function secretKey(): string {
  const key = korapayMode() === "live"
    ? Deno.env.get("KORAPAY_LIVE_SECRET_KEY")
    : Deno.env.get("KORAPAY_TEST_SECRET_KEY");
  if (!key) throw new Error(`KORAPAY_${korapayMode().toUpperCase()}_SECRET_KEY is not set`);
  return key;
}

export function publicKey(): string | null {
  return korapayMode() === "live"
    ? Deno.env.get("KORAPAY_LIVE_PUBLIC_KEY") ?? null
    : Deno.env.get("KORAPAY_TEST_PUBLIC_KEY") ?? null;
}

function baseUrl(): string {
  return Deno.env.get("KORAPAY_BASE_URL") ?? DEFAULT_BASE;
}

export interface ChargeInit {
  amountCents: number;
  currency?: string;
  reference: string;
  customerName: string;
  customerEmail: string;
  notificationUrl: string;
}

export interface ChargeResult {
  ok: boolean;
  checkoutUrl?: string;
  reference: string;
  raw: unknown;
  error?: string;
  headers?: Record<string, string>;
}

/** Creates a hosted-checkout charge. Amount is in cents, as Korapay expects. */
export async function initializeCharge(input: ChargeInit): Promise<ChargeResult> {
  const body = {
    amount: input.amountCents,
    currency: input.currency ?? "USD",
    reference: input.reference,
    customer: { name: input.customerName, email: input.customerEmail },
    notification_url: input.notificationUrl,
    // No redirect_url: checkout runs in the app's embedded WebView and the
    // result comes back through the webhook, so a post-payment bounce would
    // only take the user somewhere we cannot read.
  };

  const res = await fetch(`${baseUrl()}/charges/initialize`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${secretKey()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    // The bearer key rides on this request: a redirect means a wrong
    // KORAPAY_BASE_URL, and following it would hand the key to wherever it
    // points. The API answers in place, so refuse rather than follow.
    redirect: "error",
  });

  const raw = await res.json().catch(() => ({}));
  if (!res.ok || (raw as { status?: boolean }).status === false) {
    const detail =
      (raw as { message?: string }).message ??
      (raw as { error?: string }).error ??
      JSON.stringify(raw).slice(0, 200);
    return {
      ok: false,
      reference: input.reference,
      raw,
      error: detail ? `http_${res.status}:${detail}` : `http_${res.status}`,
      headers: Object.fromEntries(res.headers.entries()),
    };
  }
  const checkoutUrl = (raw as { data?: { checkout_url?: string } }).data?.checkout_url;
  return { ok: true, checkoutUrl, reference: input.reference, raw };
}

export interface DisburseInit {
  amountCents: number;
  currency?: string;
  reference: string;
  bankAccount: { bank_code: string; account_number: string; account_name: string };
  narration?: string;
}

/** Sends a payout to a creator's bank account. */
export async function disburse(input: DisburseInit): Promise<ChargeResult> {
  const body = {
    reference: input.reference,
    destination: {
      type: "bank_account",
      amount: input.amountCents,
      currency: input.currency ?? "USD",
      narration: input.narration ?? "Sophie payout",
      bank_account: input.bankAccount,
    },
  };
  const res = await fetch(`${baseUrl()}/transactions/disburse`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${secretKey()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    redirect: "error",
  });
  const raw = await res.json().catch(() => ({}));
  if (!res.ok || (raw as { status?: boolean }).status === false) {
    return { ok: false, reference: input.reference, raw, error: `http_${res.status}` };
  }
  return { ok: true, reference: input.reference, raw };
}

/**
 * Verifies a webhook signature. Korapay signs the raw request body with
 * HMAC-SHA256 using the secret key and sends it in `x-korapay-signature`.
 * The raw body string must be passed in, not a re-serialised object.
 */
export async function verifyWebhook(rawBody: string, signature: string | null): Promise<boolean> {
  if (!signature) return false;
  const expected = await hmacSha256Hex(secretKey(), rawBody);
  return safeEqual(expected, signature);
}
