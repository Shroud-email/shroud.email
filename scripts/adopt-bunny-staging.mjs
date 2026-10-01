// One-time bootstrap for the existing staging pair, not a site uploader.
// Never creates/deletes zones, changes cache settings, or detaches middleware.
import { pathToFileURL } from "node:url";
import { setTimeout } from "node:timers/promises";

const STORAGE_ID = 1687847;
const PULL_ID = 6214167;
const NAME = "shroud-email-website-staging";
const STORAGE = `https://uk.storage.bunnycdn.com/${NAME}/_bunny/site.json`;
const PUBLIC = "https://shroud-email-website-staging.b-cdn.net/_bunny/site.json";
const blockRule = {
  Description: "bunny sites: block site state access",
  Enabled: true,
  ActionType: 4,
  TriggerMatchingType: 0,
  Triggers: [{ Type: 0, PatternMatches: ["*/_bunny/*"], PatternMatchingType: 0 }],
};

export async function adoptStaging(apiKey, initialize, fetch = globalThis.fetch) {
  if (!apiKey) throw new Error("Missing BUNNY_API_KEY");
  async function core(path, method = "GET", body) {
    const response = await fetch(`https://api.bunny.net/${path}`, {
      method,
      headers: { AccessKey: apiKey, "Content-Type": "application/json" },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (!response.ok) throw new Error(`Bunny ${method} ${path}: HTTP ${response.status}`);
    return method === "GET" ? response.json() : undefined;
  }
  const zone = await core(`storagezone/${STORAGE_ID}`);
  const pull = await core(`pullzone/${PULL_ID}`);
  if (zone.Id !== STORAGE_ID || zone.Name !== NAME || zone.Region?.toLowerCase() !== "uk" ||
      pull.Id !== PULL_ID || pull.Name !== NAME || pull.StorageZoneId !== STORAGE_ID || pull.OriginType !== 2) {
    throw new Error("Existing staging resource pair does not match; refusing adoption");
  }
  if (!zone.Password) throw new Error("Storage credential missing from zone response");
  const stateResponse = await fetch(STORAGE, { headers: { AccessKey: zone.Password } });
  if (stateResponse.ok) {
    const state = await stateResponse.json();
    if (state.version !== 2 || state.name !== NAME || state.storageZoneId !== STORAGE_ID ||
        state.pullZoneId !== PULL_ID || !Array.isArray(state.deploys)) {
      throw new Error("Existing Sites metadata differs; refusing to overwrite it");
    }
    console.log("Staging is already initialized; metadata left unchanged.");
    return;
  }
  if (stateResponse.status !== 404) throw new Error(`Metadata read: HTTP ${stateResponse.status}`);
  if (!initialize) throw new Error("Staging needs initialization. Re-run with initialize_sites=true after reviewing the README.");

  // Protect the state before writing it. Fail closed if propagation isn't confirmed.
  const existing = (pull.EdgeRules ?? []).find((r) => r.Description === blockRule.Description);
  if (existing) {
    if (!existing.Enabled || existing.ActionType !== 4 || existing.TriggerMatchingType !== 0 ||
        existing.Triggers?.length !== 1 || existing.Triggers[0].Type !== 0 ||
        existing.Triggers[0].PatternMatchingType !== 0 ||
        JSON.stringify(existing.Triggers[0].PatternMatches) !== JSON.stringify(["*/_bunny/*"])) {
      throw new Error("Existing state-protection rule differs; refusing to replace it");
    }
  } else {
    await core(`pullzone/${PULL_ID}/edgerules/addOrUpdate`, "POST", blockRule);
  }
  let protectedState = false;
  for (let attempt = 0; attempt < 12; attempt++) {
    const response = await fetch(`${PUBLIC}?adoption_check=${Date.now()}-${attempt}`, { redirect: "manual" });
    if (response.status === 403) { protectedState = true; break; }
    await setTimeout(5000);
  }
  if (!protectedState) throw new Error("State protection not confirmed; no metadata written. Retry after rule propagation.");
  // Recheck rather than overwrite metadata created by another operator.
  const recheck = await fetch(STORAGE, { headers: { AccessKey: zone.Password } });
  if (recheck.status !== 404) throw new Error("Metadata changed during initialization; refusing to overwrite it");
  const response = await fetch(STORAGE, {
    method: "PUT",
    headers: { AccessKey: zone.Password, "Content-Type": "application/json" },
    body: JSON.stringify({ version: 2, name: NAME, storageZoneId: STORAGE_ID, pullZoneId: PULL_ID, deploys: [] }),
  });
  if (!response.ok) throw new Error(`Metadata initialization: HTTP ${response.status}`);
  console.log("Initialized existing staging pair; cache settings, middleware, and root files unchanged.");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await adoptStaging(process.env.BUNNY_API_KEY, process.env.INITIALIZE_SITES === "true");
}
