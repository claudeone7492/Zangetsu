import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std/assert/mod.ts";
import {
  amountToMajorUnits,
  flutterwaveConfigured,
  resolveFlutterwaveMode,
  verifyWebhookHash,
} from "./flutterwave.ts";

Deno.test("unset FLUTTERWAVE_MODE resolves to live", () => {
  assertEquals(resolveFlutterwaveMode(undefined), "live");
  assertEquals(resolveFlutterwaveMode(""), "live");
});

Deno.test("an explicit mode is honoured, case/space insensitive", () => {
  assertEquals(resolveFlutterwaveMode("live"), "live");
  assertEquals(resolveFlutterwaveMode(" LIVE "), "live");
  assertEquals(resolveFlutterwaveMode("test"), "test");
  assertEquals(resolveFlutterwaveMode("sandbox"), "test");
});

Deno.test("an unrecognised mode throws rather than picking test", () => {
  assertThrows(() => resolveFlutterwaveMode("production"));
  assertThrows(() => resolveFlutterwaveMode("liv"));
});

// The paywall quotes cents; Flutterwave charges major units.
Deno.test("amountToMajorUnits converts cents to the charged figure", () => {
  assertEquals(amountToMajorUnits(349), 3.49);
  assertEquals(amountToMajorUnits(76), 0.76);
  assertEquals(amountToMajorUnits(100), 1);
  assertEquals(amountToMajorUnits(0), 0);
});

Deno.test("webhook hash verification fails closed", () => {
  assertEquals(verifyWebhookHash("hash", "hash"), true);
  assertEquals(verifyWebhookHash("nope", "hash"), false);
  assertEquals(verifyWebhookHash(null, "hash"), false);
  assertEquals(verifyWebhookHash("hash", ""), false);
});

Deno.test("configured reflects the selected mode's secret key", () => {
  const names = [
    "FLUTTERWAVE_MODE",
    "FLUTTERWAVE_LIVE_SECRET_KEY",
    "FLUTTERWAVE_TEST_SECRET_KEY",
    "FLUTTERWAVE_SECRETE_KEY",
  ] as const;
  const saved = names.map((name) => [name, Deno.env.get(name)] as const);
  try {
    Deno.env.set("FLUTTERWAVE_MODE", "test");
    Deno.env.delete("FLUTTERWAVE_TEST_SECRET_KEY");
    Deno.env.delete("FLUTTERWAVE_LIVE_SECRET_KEY");
    Deno.env.delete("FLUTTERWAVE_SECRETE_KEY");
    assertEquals(flutterwaveConfigured(), false);

    Deno.env.set("FLUTTERWAVE_TEST_SECRET_KEY", "sk_test_placeholder");
    assertEquals(flutterwaveConfigured(), true);

    // Live mode also accepts the historical `FLUTTERWAVE_SECRETE_KEY` name.
    Deno.env.set("FLUTTERWAVE_MODE", "live");
    Deno.env.delete("FLUTTERWAVE_LIVE_SECRET_KEY");
    Deno.env.set("FLUTTERWAVE_SECRETE_KEY", "FLW_SECRETE_KEY");
    assertEquals(flutterwaveConfigured(), true);
  } finally {
    for (const [name, value] of saved) {
      value === undefined ? Deno.env.delete(name) : Deno.env.set(name, value);
    }
  }
});
