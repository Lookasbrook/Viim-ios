import { Router } from "express";
import { FuelPriceProviderError, getPublicFuelPrice } from "../services/fuelPriceProvider.js";

const LOCATION_PATTERN = /^[\p{L}\p{M} .'-]{1,80}$/u;
const COUNTRY_PATTERN = /^[A-Z]{2}$/;
const REGION_PATTERN = /^[A-Z]{2,16}$/;
const FUEL_TYPES = new Set(["gasoline", "diesel", "gasolineHybrid", "dieselHybrid", "electric"]);

export function createFuelPricesRouter({ getFuelPrice = getPublicFuelPrice } = {}) {
  const router = Router();

  router.get("/current", async (request, response) => {
    const countryCode = String(request.query.country ?? "").trim().toUpperCase();
    const regionCode = String(request.query.region ?? "").trim().toUpperCase();
    const locality = String(request.query.locality ?? "").trim();
    const fuelType = String(request.query.fuelType ?? "").trim();

    if (!COUNTRY_PATTERN.test(countryCode) ||
        !REGION_PATTERN.test(regionCode) ||
        !LOCATION_PATTERN.test(locality) ||
        !FUEL_TYPES.has(fuelType)) {
      return response.status(400).json({ error: "invalid_request" });
    }

    try {
      const quote = await getFuelPrice({ countryCode, regionCode, locality, fuelType });
      response.set("Cache-Control", "public, max-age=3600, stale-if-error=86400");
      return response.json(quote);
    } catch (error) {
      if (error instanceof FuelPriceProviderError) {
        return response.status(error.statusCode).json({ error: error.code });
      }
      return response.status(502).json({ error: "fuel_price_provider_unavailable" });
    }
  });

  return router;
}
