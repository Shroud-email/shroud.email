// GB + the Crown dependencies (Guernsey, Jersey, Isle of Man) share the UK
// billing entity in Paddle. Missing country data also keeps the static UK
// default rather than making an unsupported geographic assumption.
const UK_COUNTRY_CODES = new Set(["GB", "GG", "JE", "IM"]);

export function usesUKPricing(country: string | null): boolean {
  return country === null || UK_COUNTRY_CODES.has(country.toUpperCase());
}
