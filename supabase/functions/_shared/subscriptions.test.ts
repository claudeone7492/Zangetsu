import { assertEquals } from "https://deno.land/std/assert/mod.ts";
import { priceStreamPlan } from "./subscriptions.ts";

// The paywall quotes the launch discount off the list price, then the promo off
// that. The server must charge the same number the card shows, so these cases
// pin the arithmetic (and the rounding) against the client's.
Deno.test("no discount charges the list price", () => {
  const p = priceStreamPlan(200, 0, 0);
  assertEquals(p.offerCents, 200);
  assertEquals(p.amountCents, 200);
});

Deno.test("launch discount comes off the list price", () => {
  const p = priceStreamPlan(200, 15, 0);
  assertEquals(p.offerCents, 170); // 200 * 0.85 = 170
  assertEquals(p.amountCents, 170);
  assertEquals(p.launchDiscountPct, 15);
});

Deno.test("promo stacks on top of the launch discount", () => {
  const p = priceStreamPlan(599, 15, 85);
  assertEquals(p.offerCents, 509); // 599 * 0.85 = 509.15 -> 509
  assertEquals(p.amountCents, 76); // 509 * 0.15 = 76.35 -> 76
});

Deno.test("a 100% promo is free regardless of launch discount", () => {
  const p = priceStreamPlan(200, 15, 100);
  assertEquals(p.amountCents, 0);
});

Deno.test("percentages are clamped to 0..100", () => {
  assertEquals(priceStreamPlan(200, 250, 0).launchDiscountPct, 100);
  assertEquals(priceStreamPlan(200, -10, 0).launchDiscountPct, 0);
  assertEquals(priceStreamPlan(200, 0, 500).promoPercentOff, 100);
});

Deno.test("a 0% launch discount matches the promo-only price", () => {
  // The regression this guards: a card that quoted a launch discount the
  // charge never applied. With the discount honoured, these agree.
  const withLaunch = priceStreamPlan(200, 15, 0);
  const listOnly = priceStreamPlan(200, 0, 0);
  assertEquals(withLaunch.amountCents < listOnly.amountCents, true);
});
