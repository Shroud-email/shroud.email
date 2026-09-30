import { assertEquals } from "jsr:@std/assert@^1.0.14";
import { usesUKPricing } from "./pricing-country.ts";

Deno.test("missing country keeps the UK default", () => {
  assertEquals(usesUKPricing(null), true);
});

Deno.test("GB uses UK pricing", () => {
  assertEquals(usesUKPricing("GB"), true);
});

Deno.test("worldwide countries do not use UK pricing", () => {
  assertEquals(usesUKPricing("US"), false);
});
