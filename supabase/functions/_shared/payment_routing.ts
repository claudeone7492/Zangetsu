// Gateway routing for the paywall.
//
// Zangetsu sells one USD-priced subscription, but the customer pays through
// whichever gateway can actually take their money. Korapay is the cheaper rail
// where the business account has the local currency activated; Flutterwave
// covers the rest of the world (USD cards, Europe, and the African markets
// Korapay's live account is not enabled for).
//
// The Korapay set below is not a copy of Korapay's marketing coverage. It is
// the live account's activated collection currencies, read from
// `GET /merchant/api/v1/balances` on 2026-11-26:
//
//   GHS, KES, NGN, USD, XAF, XOF, ZAR
//
// USD is deliberately left to Flutterwave so dollar collection (US, UK, EU and
// anywhere else outside the local rails) runs on the global card acquirer.
// The test keys also report EGP and TZS, but the live keys do not, so Egypt and
// Tanzania are routed to Flutterwave rather than promising a rail that would
// fail at checkout. Update `KORA_CURRENCIES` (or set
// `KORA_ACTIVE_CURRENCIES`) when the live account enables another currency.
//
// Flutterwave's live account has 66 settlement currencies, including every
// currency Korapay has plus EGP, TZS, UGX, RWF, MWK, ZMW, SLL, EUR, GBP and
// USD, so it is the default for every country Korapay does not cover.

export type PaymentProvider = "korapay" | "flutterwave";

/** Countries whose local currency is active on the Korapay live account. */
export const KORA_COUNTRY_CURRENCIES: Readonly<Record<string, string>> = {
  // NGN
  NG: "NGN",
  // GHS
  GH: "GHS",
  // KES
  KE: "KES",
  // ZAR
  ZA: "ZAR",
  // XOF (West African Economic and Monetary Union)
  BJ: "XOF",
  BF: "XOF",
  CI: "XOF",
  GW: "XOF",
  ML: "XOF",
  NE: "XOF",
  SN: "XOF",
  TG: "XOF",
  // XAF (Central African Economic and Monetary Community)
  CM: "XAF",
  CF: "XAF",
  TD: "XAF",
  CG: "XAF",
  GA: "XAF",
  GQ: "XAF",
};

/** Collection currencies the Korapay live account is activated for. */
export const KORA_CURRENCIES: ReadonlySet<string> = new Set([
  "NGN",
  "GHS",
  "KES",
  "ZAR",
  "XOF",
  "XAF",
]);

/**
 * Ops override: `KORA_ACTIVE_CURRENCIES=NGN,GHS,...` lets the live activation
 * set change without a redeploy. An empty or unset value keeps the snapshot
 * above, so a typo never silently disables Korapay.
 */
export function koraCurrencies(): ReadonlySet<string> {
  const raw = Deno.env.get("KORA_ACTIVE_CURRENCIES");
  if (!raw) return KORA_CURRENCIES;
  const parsed = raw
    .split(",")
    .map((value) => value.trim().toUpperCase())
    .filter(Boolean);
  return parsed.length ? new Set(parsed) : KORA_CURRENCIES;
}

/** Headers a CDN or proxy may set with the caller's country. */
const COUNTRY_HEADERS = [
  "cf-ipcountry",
  "x-country-code",
  "x-vercel-ip-country",
  "x-geo-country",
  "x-appengine-country",
  "x-client-country",
] as const;

export function normalizeCountry(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const code = value.trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(code)) return null;
  // Cloudflare uses XX for unknown and T1 for Tor.
  if (code === "XX" || code === "T1") return null;
  return code;
}

/** Country from a trusted edge header, if the deployment sits behind one. */
export function countryFromHeaders(headers: Headers): string | null {
  for (const name of COUNTRY_HEADERS) {
    const code = normalizeCountry(headers.get(name));
    if (code) return code;
  }
  return null;
}

/** First public client IP from the proxy chain. */
export function clientIp(headers: Headers): string | null {
  const forwarded = headers.get("x-forwarded-for");
  const candidates = [
    ...(forwarded ? forwarded.split(",") : []),
    headers.get("x-real-ip") ?? "",
  ];
  for (const raw of candidates) {
    const ip = raw.trim();
    if (!ip || isPrivateIp(ip)) continue;
    return ip;
  }
  return null;
}

function isPrivateIp(ip: string): boolean {
  if (ip === "::1" || ip.startsWith("fc") || ip.startsWith("fd")) return true;
  if (ip.startsWith("fe80:")) return true;
  const v4 = ip.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!v4) return false;
  const [a, b] = [Number(v4[1]), Number(v4[2])];
  return (
    a === 10 ||
    a === 127 ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168)
  );
}

const geoCache = new Map<string, { country: string | null; at: number }>();
const GEO_TTL_MS = 6 * 60 * 60 * 1000;

/**
 * Best-effort IP → country. The paywall must not stall on a third-party lookup,
 * so this is bounded to 1.5s, cached for six hours, and a failure simply falls
 * through to the client hint or Flutterwave (the widest coverage).
 */
export async function lookupCountryByIp(
  ip: string,
  fetchImpl: typeof fetch = fetch,
): Promise<string | null> {
  const cached = geoCache.get(ip);
  if (cached && Date.now() - cached.at < GEO_TTL_MS) return cached.country;

  try {
    const res = await fetchImpl(
      `https://ipwho.is/${encodeURIComponent(ip)}?fields=country_code`,
      { signal: AbortSignal.timeout(1500) },
    );
    if (!res.ok) return null;
    const raw = (await res.json()) as {
      success?: boolean;
      country_code?: string;
    };
    const country = raw.success === false
      ? null
      : normalizeCountry(raw.country_code);
    geoCache.set(ip, { country, at: Date.now() });
    return country;
  } catch {
    return null;
  }
}

/**
 * Resolves the country the payment should be routed for. Trusted edge headers
 * win, then the caller's IP, then the client's locale hint. The hint is only a
 * tie-breaker: a caller can lie about it, but it cannot change the price and
 * both gateways charge the same amount.
 */
export async function resolvePaymentCountry(
  req: Request,
  hint?: string,
): Promise<string | null> {
  const fromHeaders = countryFromHeaders(req.headers);
  if (fromHeaders) return fromHeaders;

  const ip = clientIp(req.headers);
  if (ip) {
    const fromIp = await lookupCountryByIp(ip);
    if (fromIp) return fromIp;
  }

  return normalizeCountry(hint);
}

export interface ProviderOptions {
  /** Currencies the Korapay account can collect in. */
  koraCurrencies?: ReadonlySet<string>;
  korapayConfigured?: boolean;
  flutterwaveConfigured?: boolean;
}

/**
 * Picks the gateway for a country. Korapay is preferred only where its live
 * account has the local currency; everything else goes to Flutterwave. If the
 * preferred gateway is not configured, the other one is used so an unset
 * Flutterwave key never breaks the existing Korapay flow (and vice versa).
 */
export function providerForCountry(
  country: string | null,
  options: ProviderOptions = {},
): PaymentProvider {
  const code = normalizeCountry(country);
  const currency = code ? KORA_COUNTRY_CURRENCIES[code] : undefined;
  const activeCurrencies = options.koraCurrencies ?? koraCurrencies();
  const koraConfigured = options.korapayConfigured ?? true;
  const flutterwaveConfigured = options.flutterwaveConfigured ?? true;

  const preferred: PaymentProvider = currency && activeCurrencies.has(currency)
    ? "korapay"
    : "flutterwave";

  if (preferred === "korapay" && !koraConfigured) {
    return flutterwaveConfigured ? "flutterwave" : "korapay";
  }
  if (preferred === "flutterwave" && !flutterwaveConfigured) {
    return koraConfigured ? "korapay" : "flutterwave";
  }
  return preferred;
}

/** Test seam: clears the IP lookup cache. */
export function resetGeoCacheForTest(): void {
  geoCache.clear();
}

export const LEGACY_PAYMENT_RETURN_URL =
  "https://zangetsu.online/payment/success";

const DEFAULT_RETURN_HOSTS =
  "zangetsu.online,edgesenterprise.com,www.edgesenterprise.com";

export interface ReturnUrlOptions {
  /** Base URL override; `/payment/return` is appended. */
  base?: string;
  /** Comma-separated hosts allowed to receive the callback. */
  allowedHosts?: string;
}

/**
 * The callback URL handed to the gateway.
 *
 * The app sends the URL its WebView intercepts. Older builds send nothing, so
 * they fall back to the legacy URL rather than a domain they cannot catch —
 * deploying this function first must not strand them. A client hint is an
 * open-redirect sink unless pinned, so only HTTPS URLs on the allowlist and on
 * a payment-return path are accepted.
 */
export function resolvePaymentReturnUrl(
  clientHint?: string,
  options: ReturnUrlOptions = {},
): string {
  const hosts = new Set(
    (options.allowedHosts ?? DEFAULT_RETURN_HOSTS)
      .split(",")
      .map((host) => host.trim().toLowerCase())
      .filter(Boolean),
  );

  const accepted = (raw: string | undefined): string | null => {
    if (!raw) return null;
    try {
      const url = new URL(raw);
      if (url.protocol !== "https:") return null;
      if (!hosts.has(url.hostname.toLowerCase())) return null;
      if (url.search || url.hash) return null;
      const path = url.pathname.replace(/\/+$/, "") || "/";
      if (path !== "/payment/return" && path !== "/payment/success") {
        return null;
      }
      return url.toString();
    } catch {
      return null;
    }
  };

  if (options.base) {
    const override = accepted(
      `${options.base.replace(/\/+$/, "")}/payment/return`,
    );
    if (override) return override;
  }

  return accepted(clientHint) ?? LEGACY_PAYMENT_RETURN_URL;
}
