import { assertEquals } from "https://deno.land/std/assert/mod.ts";
import {
  clientIp,
  countryFromHeaders,
  LEGACY_PAYMENT_RETURN_URL,
  lookupCountryByIp,
  normalizeCountry,
  providerForCountry,
  resetGeoCacheForTest,
  resolvePaymentCountry,
  resolvePaymentReturnUrl,
} from "./payment_routing.ts";

// Korapay routes only where the live account has the local currency active.
Deno.test("Korapay covers the activated local-currency markets", () => {
  for (const country of ["NG", "GH", "KE", "ZA", "SN", "CI", "CM", "GA"]) {
    assertEquals(providerForCountry(country), "korapay", country);
  }
});

// Everything else goes to Flutterwave: USD cards, Europe, and the African
// markets whose currency the live Korapay account has not enabled (notably
// Egypt and Tanzania, which only the test keys report).
Deno.test("Flutterwave covers dollar payments and the rest of the world", () => {
  for (
    const country of [
      "US",
      "GB",
      "DE",
      "FR",
      "IN",
      "BR",
      "JP",
      "EG",
      "TZ",
      "UG",
      "RW",
      "MW",
      "ZM",
      "AU",
    ]
  ) {
    assertEquals(providerForCountry(country), "flutterwave", country);
  }
});

Deno.test("an unknown country falls back to Flutterwave", () => {
  assertEquals(providerForCountry(null), "flutterwave");
  assertEquals(providerForCountry(""), "flutterwave");
  assertEquals(providerForCountry("ZZ"), "flutterwave");
});

Deno.test("a missing gateway secret falls back to the other gateway", () => {
  assertEquals(
    providerForCountry("NG", {
      korapayConfigured: false,
      flutterwaveConfigured: true,
    }),
    "flutterwave",
  );
  assertEquals(
    providerForCountry("US", {
      korapayConfigured: true,
      flutterwaveConfigured: false,
    }),
    "korapay",
  );
  // Neither configured: keep the preferred choice so init fails with a clear
  // provider-specific error rather than silently rerouting.
  assertEquals(
    providerForCountry("US", {
      korapayConfigured: false,
      flutterwaveConfigured: false,
    }),
    "flutterwave",
  );
});

Deno.test("the ops override narrows the Korapay currency set", () => {
  const onlyGhs = new Set(["GHS"]);
  assertEquals(
    providerForCountry("NG", { koraCurrencies: onlyGhs }),
    "flutterwave",
  );
  assertEquals(
    providerForCountry("GH", { koraCurrencies: onlyGhs }),
    "korapay",
  );
});

Deno.test("normalizeCountry accepts ISO codes only", () => {
  assertEquals(normalizeCountry("ng"), "NG");
  assertEquals(normalizeCountry(" NG "), "NG");
  assertEquals(normalizeCountry("XX"), null);
  assertEquals(normalizeCountry("T1"), null);
  assertEquals(normalizeCountry("USA"), null);
  assertEquals(normalizeCountry(null), null);
  assertEquals(normalizeCountry(42), null);
});

Deno.test("countryFromHeaders reads edge headers and ignores unknown", () => {
  assertEquals(
    countryFromHeaders(new Headers({ "cf-ipcountry": "gh" })),
    "GH",
  );
  assertEquals(
    countryFromHeaders(new Headers({ "x-vercel-ip-country": "US" })),
    "US",
  );
  assertEquals(countryFromHeaders(new Headers({ "cf-ipcountry": "XX" })), null);
  assertEquals(countryFromHeaders(new Headers()), null);
});

Deno.test("clientIp skips loopback and private hops", () => {
  assertEquals(
    clientIp(new Headers({ "x-forwarded-for": "10.0.0.5, 41.1.2.3" })),
    "41.1.2.3",
  );
  assertEquals(
    clientIp(new Headers({ "x-real-ip": "192.168.1.9" })),
    null,
  );
  assertEquals(clientIp(new Headers()), null);
});

Deno.test("IP lookup resolves a country and caches failures", async () => {
  resetGeoCacheForTest();
  let calls = 0;
  const fakeFetch: typeof fetch = (input) => {
    calls++;
    assertEquals(String(input).includes("/203.0.113.9"), true);
    return Promise.resolve(
      new Response(JSON.stringify({ success: true, country_code: "ke" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );
  };

  assertEquals(await lookupCountryByIp("203.0.113.9", fakeFetch), "KE");
  // Cached: the second call must not hit the network.
  assertEquals(await lookupCountryByIp("203.0.113.9", fakeFetch), "KE");
  assertEquals(calls, 1);
});

Deno.test("resolvePaymentCountry prefers headers, then hint", async () => {
  const req = new Request("https://example.test/", {
    headers: { "cf-ipcountry": "NG" },
  });
  assertEquals(await resolvePaymentCountry(req, "US"), "NG");

  const noIp = new Request("https://example.test/");
  assertEquals(await resolvePaymentCountry(noIp, "gh"), "GH");
  assertEquals(await resolvePaymentCountry(noIp, undefined), null);
});

Deno.test("payment return URL trusts an allowlisted app hint", () => {
  assertEquals(
    resolvePaymentReturnUrl("https://edgesenterprise.com/payment/return"),
    "https://edgesenterprise.com/payment/return",
  );
  assertEquals(
    resolvePaymentReturnUrl("https://zangetsu.online/payment/success"),
    "https://zangetsu.online/payment/success",
  );
});

Deno.test("payment return URL falls back to the legacy URL for old apps", () => {
  assertEquals(resolvePaymentReturnUrl(), LEGACY_PAYMENT_RETURN_URL);
  assertEquals(
    resolvePaymentReturnUrl("https://evil.example/payment/return"),
    LEGACY_PAYMENT_RETURN_URL,
  );
  assertEquals(
    resolvePaymentReturnUrl("http://edgesenterprise.com/payment/return"),
    LEGACY_PAYMENT_RETURN_URL,
  );
  assertEquals(
    resolvePaymentReturnUrl("https://edgesenterprise.com/account/delete"),
    LEGACY_PAYMENT_RETURN_URL,
  );
  assertEquals(
    resolvePaymentReturnUrl(
      "https://edgesenterprise.com/payment/return?next=x",
    ),
    LEGACY_PAYMENT_RETURN_URL,
  );
});

Deno.test("PAYMENT_RETURN_BASE_URL overrides the app hint", () => {
  assertEquals(
    resolvePaymentReturnUrl("https://zangetsu.online/payment/success", {
      base: "https://edgesenterprise.com",
    }),
    "https://edgesenterprise.com/payment/return",
  );
  assertEquals(
    resolvePaymentReturnUrl("https://edgesenterprise.com/payment/return", {
      base: "https://evil.example",
    }),
    "https://edgesenterprise.com/payment/return",
  );
});
