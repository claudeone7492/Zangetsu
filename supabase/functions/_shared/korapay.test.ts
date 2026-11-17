import { assertEquals, assertThrows } from "https://deno.land/std/assert/mod.ts";
import { resolveKorapayMode } from "./korapay.ts";

// Production is the safe default: a live deployment must never be dropped onto
// the sandbox keys by an unset or misspelled KORAPAY_MODE.
Deno.test("unset KORAPAY_MODE resolves to live", () => {
  assertEquals(resolveKorapayMode(undefined), "live");
  assertEquals(resolveKorapayMode(""), "live");
});

Deno.test("explicit live resolves to live, case/space insensitive", () => {
  assertEquals(resolveKorapayMode("live"), "live");
  assertEquals(resolveKorapayMode("LIVE"), "live");
  assertEquals(resolveKorapayMode("  Live  "), "live");
});

Deno.test("explicit test/sandbox resolves to test", () => {
  assertEquals(resolveKorapayMode("test"), "test");
  assertEquals(resolveKorapayMode("TEST"), "test");
  assertEquals(resolveKorapayMode("sandbox"), "test");
});

Deno.test("an unrecognised mode throws rather than silently picking test", () => {
  assertThrows(() => resolveKorapayMode("production"));
  assertThrows(() => resolveKorapayMode("staging"));
  assertThrows(() => resolveKorapayMode("liv"));
});
