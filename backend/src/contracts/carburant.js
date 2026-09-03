export const CARBURANT_CONTRACT_VERSION = "carburant-contract-v1";

export const FUEL_COST_STATES = Object.freeze([
  "pending",
  "unavailable",
  "estimated",
  "confirmed"
]);

export const PRICE_EVIDENCE_KINDS = Object.freeze([
  "administered_exact",
  "official_average",
  "cached_stale"
]);

export const TRIP_ROLES = Object.freeze([
  "conducteur",
  "passager_transport",
  "inconnu"
]);

export const LEGACY_TRIP_ROLE_ALIASES = Object.freeze({
  passager: "passager_transport",
  bus: "passager_transport"
});

export const CARBURANT_FEATURE_FLAGS = Object.freeze([
  "gpsSessionSplit",
  "physicalFuelModel",
  "transitClassifier"
]);
