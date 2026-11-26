// Flutterwave v3 client. LIVE keys are the default; FLUTTERWAVE_MODE=test
// opts a deployment back onto the sandbox keys.
//
// Only the secret key is used server-side. The public key is never echoed to
// the client because the paywall uses Flutterwave's hosted checkout, and the
// encryption key is intentionally unused: it exists for direct card charges
// that handle PAN data, which this integration deliberately avoids.
//
// Amounts: the rest of the paywall works in cents, Flutterwave takes major
// units ("3.49" for USD), so `amountToMajorUnits` is the one conversion point.

import { safeEqual } from "./cors.ts";

const DEFAULT_BASE = "https://api.flutterwave.com/v3";

/** Pure mode resolution, split out from the env read so it is testable. */
export function resolveFlutterwaveMode(
  raw: string | undefined,
): "test" | "live" {
  const value = (raw ?? "").trim().toLowerCase();
  if (value === "test" || value === "sandbox") return "test";
  if (value === "" || value === "live") return "live";
  throw new Error(
    `FLUTTERWAVE_MODE must be "live" or "test" (got "${raw}")`,
  );
}

export function flutterwaveMode(): "test" | "live" {
  return resolveFlutterwaveMode(Deno.env.get("FLUTTERWAVE_MODE"));
}

function firstEnv(names: readonly string[]): string | undefined {
  for (const name of names) {
    const value = Deno.env.get(name);
    if (value) return value;
  }
  return undefined;
}

// The live aliases cover the keys already registered on this project
// (`FLUTTERWAVE_SECRETE_KEY` keeps its historical spelling). Test mode never
// falls back to them: a test deployment must not be able to charge live.
const LIVE_SECRET_NAMES = [
  "FLUTTERWAVE_LIVE_SECRET_KEY",
  "FLUTTERWAVE_SECRETE_KEY",
  "FLUTTERWAVE_SECRET_KEY",
] as const;

function secretKey(): string {
  const key = flutterwaveMode() === "live"
    ? firstEnv(LIVE_SECRET_NAMES)
    : Deno.env.get("FLUTTERWAVE_TEST_SECRET_KEY") ?? undefined;
  if (!key) {
    throw new Error(
      `FLUTTERWAVE_${flutterwaveMode().toUpperCase()}_SECRET_KEY is not set`,
    );
  }
  return key;
}

/** True when the selected mode has a secret key, without throwing. */
export function flutterwaveConfigured(): boolean {
  try {
    secretKey();
    return true;
  } catch {
    return false;
  }
}

function baseUrl(): string {
  return Deno.env.get("FLUTTERWAVE_BASE_URL") ?? DEFAULT_BASE;
}

export function amountToMajorUnits(amountCents: number): number {
  return Math.round(amountCents) / 100;
}

export interface ChargeInit {
  amountCents: number;
  currency?: string;
  reference: string;
  customerName: string;
  customerEmail: string;
  redirectUrl?: string;
  narration?: string;
}

export interface ChargeResult {
  ok: boolean;
  checkoutUrl?: string;
  reference: string;
  raw: unknown;
  error?: string;
}

/** Creates a hosted-checkout payment and returns its URL. */
export async function initializeCharge(
  input: ChargeInit,
): Promise<ChargeResult> {
  const body = {
    tx_ref: input.reference,
    amount: amountToMajorUnits(input.amountCents),
    currency: input.currency ?? "USD",
    ...(input.redirectUrl ? { redirect_url: input.redirectUrl } : {}),
    customer: { email: input.customerEmail, name: input.customerName },
    customizations: {
      title: "Zangetsu",
      description: input.narration ?? "Zangetsu subscription",
    },
    meta: { reference: input.reference },
  };

  try {
    const res = await fetch(`${baseUrl()}/payments`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secretKey()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      // The bearer key rides on this request: a redirect means a wrong
      // FLUTTERWAVE_BASE_URL, and following it would hand the key to wherever
      // it points. The API answers in place, so refuse rather than follow.
      redirect: "error",
    });

    const raw = await res.json().catch(() => ({}));
    const status = (raw as { status?: string }).status;
    const link = (raw as { data?: { link?: string } }).data?.link;
    if (!res.ok || status !== "success" || !link) {
      const detail = (raw as { message?: string }).message ??
        JSON.stringify(raw).slice(0, 200);
      return {
        ok: false,
        reference: input.reference,
        raw,
        error: `http_${res.status}:${detail}`,
      };
    }
    return { ok: true, checkoutUrl: link, reference: input.reference, raw };
  } catch (e) {
    return {
      ok: false,
      reference: input.reference,
      raw: null,
      error: `network:${e instanceof Error ? e.message : String(e)}`,
    };
  }
}

export interface VerifyResult {
  ok: boolean;
  status?: string;
  amountCents?: number;
  currency?: string;
  txRef?: string;
  raw?: unknown;
  error?: string;
}

/**
 * Verifies a transaction with Flutterwave before its webhook is trusted.
 * A webhook payload alone is not proof of payment; this is the server-side
 * confirmation that the tx_ref, amount and currency match what was charged.
 */
async function verifyAt(path: string): Promise<VerifyResult> {
  try {
    const res = await fetch(
      `${baseUrl()}${path}`,
      {
        headers: { Authorization: `Bearer ${secretKey()}` },
        redirect: "error",
      },
    );
    const raw = await res.json().catch(() => ({}));
    const status = (raw as { status?: string }).status;
    const data = (raw as {
      data?: {
        status?: string;
        amount?: number | string;
        currency?: string;
        tx_ref?: string;
      };
    }).data;
    if (!res.ok || status !== "success" || !data) {
      return {
        ok: false,
        raw,
        error: `http_${res.status}:${
          (raw as { message?: string }).message ?? ""
        }`,
      };
    }
    const amount = Number(data.amount);
    return {
      ok: true,
      status: data.status,
      amountCents: Number.isFinite(amount)
        ? Math.round(amount * 100)
        : undefined,
      currency: data.currency,
      txRef: data.tx_ref,
      raw,
    };
  } catch (e) {
    return {
      ok: false,
      error: `network:${e instanceof Error ? e.message : String(e)}`,
    };
  }
}

/** Verifies a charge by Flutterwave's numeric transaction id. */
export function verifyTransaction(
  id: string | number,
): Promise<VerifyResult> {
  return verifyAt(
    `/transactions/${encodeURIComponent(String(id))}/verify`,
  );
}

/**
 * Verifies a charge by our own `tx_ref`, which is what the server can look up
 * when the buyer returns without a webhook. The secret key is the proof.
 */
export function verifyTransactionByReference(
  txRef: string,
): Promise<VerifyResult> {
  return verifyAt(
    `/transactions/verify_by_reference?tx_ref=${encodeURIComponent(txRef)}`,
  );
}

/**
 * Verifies Flutterwave's `verif-hash` header. The value is the secret hash set
 * in the dashboard, compared in constant time. An unset secret fails closed so
 * an unconfigured deploy never accepts an unsigned charge confirmation.
 */
export function verifyWebhookHash(
  signature: string | null,
  secret = Deno.env.get("FLUTTERWAVE_WEBHOOK_SECRET") ?? "",
): boolean {
  if (!secret || !signature) return false;
  return safeEqual(secret, signature);
}
