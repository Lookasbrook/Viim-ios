import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";
import {
  CARBURANT_CONTRACT_VERSION,
  CARBURANT_FEATURE_FLAGS,
  FUEL_COST_STATES,
  LEGACY_TRIP_ROLE_ALIASES,
  PRICE_EVIDENCE_KINDS,
  TRIP_ROLES
} from "../src/contracts/carburant.js";

test("backend wire values match the shared carburant contract", async () => {
  const shared = JSON.parse(await readFile(
    new URL("../../shared-data/carburant-contract-v1.json", import.meta.url),
    "utf8"
  ));

  assert.equal(CARBURANT_CONTRACT_VERSION, shared.schemaVersion);
  assert.deepEqual(FUEL_COST_STATES, shared.fuelCostStates);
  assert.deepEqual(PRICE_EVIDENCE_KINDS, shared.priceEvidenceKinds);
  assert.deepEqual(TRIP_ROLES, shared.tripRoles);
  assert.deepEqual(LEGACY_TRIP_ROLE_ALIASES, shared.legacyTripRoleAliases);
  assert.deepEqual(CARBURANT_FEATURE_FLAGS, shared.featureFlags);
  assert.equal(shared.rules.modeledCostCanBeConfirmed, false);
  assert.equal(shared.rules.unknownTripIsPersisted, true);
  assert.equal(shared.rules.motorizationMayBeInferredFromSensors, false);
});
