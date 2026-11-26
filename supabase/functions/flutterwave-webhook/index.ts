// POST /functions/v1/flutterwave-webhook
// Flutterwave calls this when a hosted-checkout charge completes.
//
// The `verif-hash` header is compared against the dashboard secret hash before
// the body is trusted. A success is then confirmed with Flutterwave's
// transaction-verify endpoint, so a forged or replayed body cannot credit an
// account. Delivery idempotency is shared with the Korapay webhook through
// `payment_events`, keyed by (reference, event + status).

import { adminClient } from "../_shared/supabase.ts";
import {
  verifyTransaction,
  verifyWebhookHash,
} from "../_shared/flutterwave.ts";
import {
  markPaymentFailed,
  type PaymentRow,
  recordPaymentEvent,
  revokePayment,
  settleSuccessfulCharge,
} from "../_shared/settle.ts";
import { handleOptions, json } from "../_shared/cors.ts";

interface FlutterwaveEvent {
  event?: string;
  data?: {
    id?: number;
    tx_ref?: string;
    flw_ref?: string;
    status?: string;
    amount?: number;
    currency?: string;
  };
}

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const rawBody = await req.text();

  let event: FlutterwaveEvent;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const data = event.data ?? {};
  const reference = data.tx_ref;
  if (!reference) return json({ error: "missing_reference" }, 400);

  const status = (data.status ?? "").toLowerCase();
  const eventName = (event.event ?? "").toLowerCase();
  const refunded = eventName.includes("refund") ||
    status === "refunded" || status === "reversed";
  const succeeded = status === "successful" || status === "completed";
  // Flutterwave reuses `charge.completed` for both outcomes, so the status is
  // part of the idempotency key: a failed attempt followed by a successful
  // retry of the same tx_ref must still settle.
  const eventType = `${event.event ?? "unknown"}:${status || "unknown"}`;

  // A configured hash is always required. Without one, only a success is
  // accepted, and only because the verify call below is mandatory for it;
  // refunds and failures stay rejected so nobody can revoke access unsigned.
  const webhookSecret = Deno.env.get("FLUTTERWAVE_WEBHOOK_SECRET") ?? "";
  if (webhookSecret) {
    if (!verifyWebhookHash(req.headers.get("verif-hash"), webhookSecret)) {
      return json({ error: "invalid_signature" }, 401);
    }
  } else if (!succeeded) {
    return json({ error: "webhook_secret_not_configured" }, 503);
  }

  const db = adminClient();

  const { data: payment } = await db
    .from("payments")
    .select(
      "id, payer_session_id, receiver_session_id, product_type, amount, status, subscription_id, promo_code_used, payment_provider",
    )
    .eq("korapay_reference", reference)
    .maybeSingle();

  if (!payment) return json({ error: "unknown_reference" }, 404);

  // A Korapay reference is never settled by the Flutterwave webhook.
  if ((payment as PaymentRow).payment_provider !== "flutterwave") {
    return json({ error: "wrong_provider" }, 409);
  }

  // A success is only trusted after Flutterwave confirms it. A transient
  // verify failure returns 502 without recording the event, so Flutterwave's
  // retry can settle it later.
  if (succeeded) {
    if (data.id == null) return json({ error: "missing_transaction_id" }, 400);
    const verified = await verifyTransaction(data.id);
    if (!verified.ok || verified.status !== "successful") {
      return json(
        { error: "verification_failed", detail: verified.error },
        502,
      );
    }
    if (verified.txRef !== reference) {
      return json({ error: "reference_mismatch" }, 409);
    }
    if (verified.currency && verified.currency.toUpperCase() !== "USD") {
      await recordPaymentEvent(db, reference, eventType, data);
      return json({ received: true, status: "currency_mismatch" });
    }
    if (
      verified.amountCents != null &&
      verified.amountCents !== payment.amount
    ) {
      await recordPaymentEvent(db, reference, eventType, data);
      return json({ received: true, status: "amount_mismatch" });
    }
  }

  if (
    await recordPaymentEvent(db, reference, eventType, data) === "duplicate"
  ) {
    return json({ received: true, alreadyProcessed: true });
  }

  if (refunded) {
    await revokePayment(db, payment as PaymentRow);
    return json({
      received: true,
      status: "refunded",
      product: payment.product_type,
    });
  }

  if (!succeeded) {
    await markPaymentFailed(db, payment as PaymentRow);
    return json({ received: true, status: "failed" });
  }

  if (payment.status === "completed") {
    return json({ received: true, alreadyProcessed: true });
  }

  await settleSuccessfulCharge(db, payment as PaymentRow, reference);
  return json({
    received: true,
    status: "completed",
    product: payment.product_type,
  });
});
