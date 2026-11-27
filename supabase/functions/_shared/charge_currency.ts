// The currency a paywall charge is taken in, and the gateway that can take it.
//
// The catalogue is priced in USD, but a USD 0.75 charge cannot be collected:
// the Korapay merchant has no USD channel at all, and Flutterwave refuses any
// amount below one major unit. Both accounts do accept the payer's local
// currency, so the price is converted and charged there.
//
// Coverage below is the live accounts' answer, probed on 2026-11-27 with
// `POST /charges/initialize` (Korapay) and `POST /v3/payments` (Flutterwave):
//
//   Korapay      NGN, GHS, KES, ZAR, XOF, XAF -> 200
//                USD                          -> 409 AA021 "no channel enabled"
//   Flutterwave  USD, EUR, GBP, NGN, GHS, KES, ZAR -> 200
//                any amount below 1 major unit -> 400
//
// Korapay's `amount` is in major units (a 120000 NGN charge reads back as
// "120000.00"), not cents, so both gateways are handed a major-unit figure and
// `charge_amount` stores it in the payment's currency.
//
// Korapay also enforces per-channel minimums that are higher than one unit —
// GHS 9 is refused ("does not meet transaction limit for any payment channel")
// while GHS 10 is accepted. Those limits move, so they are not hard-coded: when
// the converted figure is under one the charge fails over to Flutterwave, which
// takes the same amount.

import {
  KORA_COUNTRY_CURRENCIES,
  providerForCountry,
  type PaymentProvider,
} from "./payment_routing.ts";

/** Currencies the Korapay live account can actually charge. */
export const KORA_CHARGE_CURRENCIES: ReadonlySet<string> = new Set([
  "NGN",
  "GHS",
  "KES",
  "ZAR",
  "XOF",
  "XAF",
]);

/**
 * Currencies the Flutterwave live account settles in. Anything Korapay cannot
 * charge is covered here, which is why this is the wider set.
 */
export const FLW_CHARGE_CURRENCIES: ReadonlySet<string> = new Set([
  "NGN",
  "GHS",
  "KES",
  "ZAR",
  "XOF",
  "XAF",
  "USD",
  "EUR",
  "GBP",
  "EGP",
  "TZS",
  "UGX",
  "RWF",
  "MWK",
  "ZMW",
  "SLL",
]);

/** ISO 4217 currencies with no minor unit: the figure is whole units. */
const ZERO_DECIMAL: ReadonlySet<string> = new Set([
  "BIF",
  "CLP",
  "DJF",
  "GNF",
  "JPY",
  "KMF",
  "KRW",
  "MGA",
  "PYG",
  "RWF",
  "UGX",
  "VND",
  "VUV",
  "XAF",
  "XOF",
  "XPF",
]);

/** Smallest charge either gateway accepts: one major unit. */
export const GATEWAY_MINIMUM_MAJOR = 1;

export function decimalsFor(currency: string): number {
  return ZERO_DECIMAL.has(currency.trim().toUpperCase()) ? 0 : 2;
}

/** Rounds a major-unit figure to the currency's smallest payable step. */
export function roundMajor(amount: number, currency: string): number {
  const scale = 10 ** decimalsFor(currency);
  return Math.round(amount * scale) / scale;
}

/** Countries on a local African rail — the $1 tier. */
/**
 * African countries. The tier follows the continent, not the rail: Korapay
 * charges $1 in the local currency where its account has it, and Flutterwave
 * collects the same $1 in USD everywhere else on the continent.
 */
export const AFRICAN_COUNTRIES: ReadonlySet<string> = new Set([
  "DZ", "AO", "BJ", "BW", "BF", "BI", "CV", "CM",
  "CF", "TD", "KM", "CG", "CD", "CI", "DJ", "EG",
  "GQ", "ER", "SZ", "ET", "GA", "GM", "GH", "GN",
  "GW", "KE", "LS", "LR", "LY", "MG", "MW", "ML",
  "MR", "MU", "MA", "MZ", "NA", "NE", "NG", "RW",
  "ST", "SN", "SC", "SL", "SO", "ZA", "SS", "SD",
  "TZ", "TG", "TN", "UG", "ZM", "ZW",
]);

export function isAfricanCountry(country: string | null): boolean {
  return AFRICAN_COUNTRIES.has((country ?? "").trim().toUpperCase());
}

/**
 * The USD-cents list price for [country]. African payers are $1 on either rail;
 * the rest of the world pays the overseas tier, which is deliberately higher so
 * promo codes stay payable — Flutterwave refuses any charge under one major
 * unit, so an 85% code against a $1 price lands on $0.15 and never starts.
 *
 * [country] must be the network's answer (`resolvePaymentCountry`), not the
 * device locale: an English (US) phone in Lagos reports US. `public.list_plans`
 * quotes the same figure from the same header, so the paywall and the charge
 * cannot disagree.
 */
export function listPriceCents(
  plan: { price_usd_cents: number; price_intl_usd_cents?: number | null },
  country: string | null,
): number {
  if (isAfricanCountry(country)) return plan.price_usd_cents;
  return plan.price_intl_usd_cents ?? plan.price_usd_cents;
}

/** The currency a payer in [country] is charged in; USD when unknown. */
export function currencyForCountry(country: string | null): string {
  const code = (country ?? "").trim().toUpperCase();
  return KORA_COUNTRY_CURRENCIES[code] ?? "USD";
}

/**
 * USD→currency snapshot. Only used when the rate API cannot be reached: a
 * stale rate beats a paywall that cannot price at all.
 */
const FALLBACK_RATES: Readonly<Record<string, number>> = {
  USD: 1,
  EUR: 0.91,
  GBP: 0.76,
  NGN: 1356,
  GHS: 11.8,
  KES: 130,
  ZAR: 17.4,
  XOF: 598,
  XAF: 598,
};

const RATE_SOURCES = [
  "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json",
  "https://latest.currency-api.pages.dev/v1/currencies/usd.json",
];
const RATE_TTL_MS = 6 * 60 * 60 * 1000;

let rateCache: { at: number; rates: Record<string, number> } | null = null;

/** USD→local rates, cached for six hours; `{}` when every source fails. */
export async function usdRates(
  fetchImpl: typeof fetch = fetch,
  now = Date.now(),
): Promise<Record<string, number>> {
  if (rateCache && now - rateCache.at < RATE_TTL_MS) return rateCache.rates;
  for (const url of RATE_SOURCES) {
    try {
      const res = await fetchImpl(url, { signal: AbortSignal.timeout(3000) });
      if (!res.ok) continue;
      const raw = (await res.json()) as { usd?: Record<string, number> };
      const table = raw.usd;
      if (!table || typeof table !== "object") continue;
      const rates: Record<string, number> = {};
      for (const [code, value] of Object.entries(table)) {
        if (typeof value === "number" && value > 0) {
          rates[code.toUpperCase()] = value;
        }
      }
      rateCache = { at: now, rates };
      return rates;
    } catch {
      // Try the mirror, then the snapshot.
    }
  }
  return {};
}

export function rateFor(
  currency: string,
  rates: Record<string, number>,
): number | null {
  const code = currency.trim().toUpperCase();
  const live = rates[code];
  if (typeof live === "number" && live > 0) return live;
  const fallback = FALLBACK_RATES[code];
  return fallback ?? null;
}

/** Converts a USD-cents price into the major-unit figure of [currency]. */
export function toMajorUnits(
  usdCents: number,
  currency: string,
  rate: number,
): number {
  return roundMajor((usdCents / 100) * rate, currency);
}

export interface ChargeOptions {
  korapayConfigured?: boolean;
  flutterwaveConfigured?: boolean;
  /** Currencies Korapay can charge; defaults to the probed live set. */
  koraCurrencies?: ReadonlySet<string>;
  /** Test seam: rate table, bypassing the cache and the network. */
  rates?: Record<string, number>;
  fetchImpl?: typeof fetch;
}

export interface ChargePlan {
  currency: string;
  /** What the gateway is asked to charge, in major units of [currency]. */
  amountMajor: number;
  /** Gateways to try, best first; empty when none can take the currency. */
  providers: PaymentProvider[];
  error?: string;
  detail?: string;
}

function supports(
  provider: PaymentProvider,
  currency: string,
  koraCurrencies: ReadonlySet<string>,
): boolean {
  return provider === "korapay"
    ? koraCurrencies.has(currency)
    : FLW_CHARGE_CURRENCIES.has(currency);
}

/**
 * Decides the charge: currency, amount in major units, and the gateways that
 * can take it. The country still picks the preferred rail (Korapay where the
 * local currency is cheaper for the business), but a currency Korapay cannot
 * charge falls through to Flutterwave instead of failing at the gateway.
 */
export async function planCharge(
  usdCents: number,
  country: string | null,
  options: ChargeOptions = {},
): Promise<ChargePlan> {
  const currency = currencyForCountry(country);
  const koraCurrencies = options.koraCurrencies ?? KORA_CHARGE_CURRENCIES;
  const korapayConfigured = options.korapayConfigured ?? true;
  const flutterwaveConfigured = options.flutterwaveConfigured ?? true;

  const preferred = providerForCountry(country, {
    koraCurrencies,
    korapayConfigured,
    flutterwaveConfigured,
  });
  const order: PaymentProvider[] = preferred === "korapay"
    ? ["korapay", "flutterwave"]
    : ["flutterwave", "korapay"];
  const providers = order.filter((provider) =>
    supports(provider, currency, koraCurrencies) &&
    (provider === "korapay" ? korapayConfigured : flutterwaveConfigured)
  );

  const rates = options.rates ?? await usdRates(options.fetchImpl);
  const rate = rateFor(currency, rates);
  if (rate == null) {
    return {
      currency,
      amountMajor: 0,
      providers,
      error: "rate_unavailable",
      detail: `no USD→${currency} rate`,
    };
  }

  const amountMajor = toMajorUnits(usdCents, currency, rate);
  if (providers.length === 0) {
    return {
      currency,
      amountMajor,
      providers,
      error: "currency_not_supported",
      detail: `no gateway can charge ${currency}`,
    };
  }
  if (amountMajor < GATEWAY_MINIMUM_MAJOR) {
    return {
      currency,
      amountMajor,
      providers,
      error: "amount_below_minimum",
      detail:
        `${currency} ${amountMajor} is below the ${GATEWAY_MINIMUM_MAJOR} ${currency} minimum`,
    };
  }

  return { currency, amountMajor, providers };
}
