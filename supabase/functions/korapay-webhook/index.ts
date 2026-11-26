// POST /functions/v1/korapay-webhook
// Korapay calls this when a charge settles, renews, fails or is refunded.
//
// The raw body is verified against the x-korapay-signature HMAC before anything
// is trusted. Every delivery is recorded in `payment_events` by (reference,
// event) so a replayed webhook is a no-op rather than a double credit.
//
// Settles both the Sophie products (vip_unlock, tips, sessions) and the
// Zangetsu stream subscriptions (subscription_stream). The lifecycle itself is
// shared with the Flutterwave webhook in `_shared/settle.ts`.

import { adminClient } from "../_shared/supabase.ts";
import { verifyWebhook } from "../_shared/korapay.ts";
import {
  markPaymentFailed,
  recordPaymentEvent,
  revokePayment,
  settleSuccessfulCharge,
  type PaymentRow,
} from "../_shared/settle.ts";
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
    .select("id, payer_session_id, receiver_session_id, product_type, amount, status, subscription_id, promo_code_used, payment_provider")
    .eq("korapay_reference", reference)
    .maybeSingle();

  if (!payment) return json({ error: "unknown_reference" }, 404);

  // A Flutterwave reference is never settled by the Korapay webhook.
  if ((payment as PaymentRow).payment_provider === "flutterwave") {
    return json({ error: "wrong_provider" }, 409);
  }

  // Idempotency by (reference, event). A unique-violation means we have seen
  // this exact delivery, so stop here.
  if (
    await recordPaymentEvent(db, reference, eventType, event.data) ===
      "duplicate"
  ) {
    return json({ received: true, alreadyProcessed: true });
  }

  const succeeded = event.event === "charge.success" &&
    event.data?.status === "success";
  const refunded = event.event === "charge.refunded" ||
    event.data?.status === "refunded";

  // A refund or chargeback revokes access immediately, subscription or not.
  if (refunded) {
    await revokePayment(db, payment as PaymentRow);
    return json({
      received: true,
      status: "refunded",
      product: payment.product_type,
    });
  }

  if (!succeeded) {
    // A failed renewal does not revoke anything here: the subscription moves to
    // grace on its own clock, and lapses only when grace runs out.
    await markPaymentFailed(db, payment as PaymentRow);
    return json({ received: true, status: "failed" });
  }

  // Already settled: nothing to do.
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
