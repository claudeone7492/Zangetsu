import { assertEquals } from "https://deno.land/std/assert/mod.ts";
import {
  currencyForCountry,
  decimalsFor,
  isAfricanRail,
  listPriceCents,
  planCharge,
  rateFor,
  roundMajor,
  toMajorUnits,
  usdRates,
} from "./charge_currency.ts";

Deno.test("country decides the charge currency, unknown falls back to USD", () => {
  assertEquals(currencyForCountry("NG"), "NGN");
  assertEquals(currencyForCountry("gh"), "GHS");
  assertEquals(currencyForCountry("KE"), "KES");
  assertEquals(currencyForCountry("US"), "USD");
  assertEquals(currencyForCountry("ZZ"), "USD");
  assertEquals(currencyForCountry(null), "USD");
});

Deno.test("zero-decimal currencies keep whole units", () => {
  assertEquals(decimalsFor("XOF"), 0);
  assertEquals(decimalsFor("XAF"), 0);
  assertEquals(decimalsFor("NGN"), 2);
  assertEquals(roundMajor(448.33, "XOF"), 448);
  assertEquals(roundMajor(1017.1567, "NGN"), 1017.16);
});

Deno.test("a USD price converts into the charged local figure", () => {
  assertEquals(toMajorUnits(75, "USD", 1), 0.75);
  assertEquals(toMajorUnits(75, "NGN", 1356.20762482), 1017.16);
  assertEquals(toMajorUnits(75, "XOF", 597.76862168), 448);
});

Deno.test("rates prefer the live table and fall back to the snapshot", () => {
  assertEquals(rateFor("NGN", { NGN: 1500 }), 1500);
  assertEquals(rateFor("NGN", {}), 1356);
  assertEquals(rateFor("ZZZ", {}), null);
});

Deno.test("usdRates reads the API once and then serves the cache", async () => {
  let calls = 0;
  const fake = (() => {
    calls++;
    return Promise.resolve(
      new Response(JSON.stringify({ usd: { ngn: 1400, xof: 600 } })),
    );
  }) as unknown as typeof fetch;

  const first = await usdRates(fake, 1_000_000);
  const second = await usdRates(fake, 1_000_001);
  assertEquals(first.NGN, 1400);
  assertEquals(second.XOF, 600);
  assertEquals(calls, 1);
});

Deno.test("a Nigerian payer is charged naira, Korapay first", async () => {
  const plan = await planCharge(75, "NG", { rates: { NGN: 1356 } });
  assertEquals(plan.error, undefined);
  assertEquals(plan.currency, "NGN");
  assertEquals(plan.amountMajor, 1017);
  assertEquals(plan.providers, ["korapay", "flutterwave"]);
});

Deno.test("a currency Korapay cannot charge falls through to Flutterwave", async () => {
  const plan = await planCharge(150, "US", { rates: { USD: 1 } });
  assertEquals(plan.error, undefined);
  assertEquals(plan.currency, "USD");
  assertEquals(plan.amountMajor, 1.5);
  assertEquals(plan.providers, ["flutterwave"]);
});

Deno.test("a charge under the gateway minimum is refused with a reason", async () => {
  const plan = await planCharge(75, "US", { rates: { USD: 1 } });
  assertEquals(plan.error, "amount_below_minimum");
  assertEquals(plan.currency, "USD");
  assertEquals(plan.amountMajor, 0.75);
});

Deno.test("an unconfigured gateway is dropped from the order", async () => {
  const noKorapay = await planCharge(75, "NG", {
    rates: { NGN: 1356 },
    korapayConfigured: false,
  });
  assertEquals(noKorapay.providers, ["flutterwave"]);

  const noFlutterwave = await planCharge(75, "NG", {
    rates: { NGN: 1356 },
    flutterwaveConfigured: false,
  });
  assertEquals(noFlutterwave.providers, ["korapay"]);

  const neither = await planCharge(75, "NG", {
    rates: { NGN: 1356 },
    korapayConfigured: false,
    flutterwaveConfigured: false,
  });
  assertEquals(neither.error, "currency_not_supported");
});

Deno.test("the rail picks the tier: African rails $1, the rest $6.99", () => {
  const plan = { price_usd_cents: 100, price_intl_usd_cents: 699 };
  assertEquals(listPriceCents(plan, "NG"), 100);
  assertEquals(listPriceCents(plan, "sn"), 100);
  assertEquals(listPriceCents(plan, "US"), 699);
  assertEquals(listPriceCents(plan, "DE"), 699);
  // Unknown country quotes the higher price: never show less than is charged.
  assertEquals(listPriceCents(plan, null), 699);
  assertEquals(isAfricanRail("KE"), true);
  assertEquals(isAfricanRail("EG"), false);
});

Deno.test("a plan with no overseas tier keeps its single price", () => {
  assertEquals(listPriceCents({ price_usd_cents: 100 }, "US"), 100);
});

Deno.test("the overseas tier keeps every promo code above the gateway floor", async () => {
  const rates = { USD: 1 };
  const full = await planCharge(699, "US", { rates });
  assertEquals(full.error, undefined);
  assertEquals(full.amountMajor, 6.99);

  const half = await planCharge(350, "US", { rates });
  assertEquals(half.error, undefined);
  assertEquals(half.amountMajor, 3.5);

  // 85% off is the deepest code in the catalogue: 699 * 0.15 rounds to $1.05.
  const deepest = await planCharge(105, "US", { rates });
  assertEquals(deepest.error, undefined);
  assertEquals(deepest.amountMajor, 1.05);

  const under = await planCharge(75, "US", { rates });
  assertEquals(under.error, "amount_below_minimum");
});

Deno.test("a currency the only configured gateway cannot take is refused", async () => {
  // USD is Flutterwave-only, so dropping Flutterwave leaves nothing.
  const plan = await planCharge(150, "US", {
    rates: { USD: 1 },
    flutterwaveConfigured: false,
  });
  assertEquals(plan.error, "currency_not_supported");
  assertEquals(plan.providers, []);
});

Deno.test("an unreachable rate API still prices from the snapshot", async () => {
  const plan = await planCharge(75, "NG", { rates: {} });
  assertEquals(plan.error, undefined);
  assertEquals(plan.currency, "NGN");
  assertEquals(plan.amountMajor, toMajorUnits(75, "NGN", 1356));
});
