import assert from "node:assert/strict";
import { once } from "node:events";
import { test } from "node:test";
import express from "express";
import { createFuelPricesRouter } from "../src/routes/fuelPrices.js";
import {
  FuelPriceProviderError,
  getPublicFuelPrice,
  resetFuelPriceCacheForTests
} from "../src/services/fuelPriceProvider.js";

const csv = `Date,Ottawa,Toronto West/Ouest,Toronto East/Est,Ontario Average/Moyenne provinciale,Fuel Type,Type de carburant\r
2026-08-24,150.0,149.0,151.0,152.0,Regular Unleaded Gasoline,Essence sans plomb\r
2026-08-31,153.0,154.0,156.0,155.0,Regular Unleaded Gasoline,Essence sans plomb\r
2026-08-31,160.0,161.0,163.0,162.0,Diesel,Carburant diesel\r
`;

function officialResponse(url = "https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv") {
  const response = new Response(csv, { status: 200, headers: { "Content-Type": "text/csv" } });
  Object.defineProperty(response, "url", {
    value: url
  });
  return response;
}

function officialResponseWithBody(body, url = "https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv") {
  const response = new Response(body, { status: 200, headers: { "Content-Type": "text/csv" } });
  Object.defineProperty(response, "url", { value: url });
  return response;
}

test("Ontario official provider returns latest Toronto gasoline average", async () => {
  resetFuelPriceCacheForTests();
  const quote = await getPublicFuelPrice({
    countryCode: "CA",
    regionCode: "ON",
    locality: "Toronto",
    fuelType: "gasoline",
    now: new Date("2026-09-02T12:00:00Z"),
    fetchImpl: async () => officialResponse()
  });

  assert.equal(quote.pricePerLiter, 1.55);
  assert.equal(quote.currency, "CAD");
  assert.equal(quote.observedAt, "2026-08-31T00:00:00.000Z");
  assert.equal(quote.source, "government_of_ontario_fuel_price_survey");
});

test("Ontario provider accepts only the exact official redirect host", async () => {
  resetFuelPriceCacheForTests();
  const quote = await getPublicFuelPrice({
    countryCode: "CA",
    regionCode: "ON",
    locality: "Toronto",
    fuelType: "gasoline",
    now: new Date("2026-09-02T12:00:00Z"),
    fetchImpl: async () => officialResponse("https://prod-energy-fuel-prices.s3.amazonaws.com/fueltypesall.csv")
  });
  assert.equal(quote.pricePerLiter, 1.55);

  resetFuelPriceCacheForTests();
  await assert.rejects(
    getPublicFuelPrice({
      countryCode: "CA",
      regionCode: "ON",
      locality: "Toronto",
      fuelType: "gasoline",
      now: new Date("2026-09-02T12:00:00Z"),
      fetchImpl: async () => officialResponse("https://prod-energy-fuel-prices.s3.amazonaws.com.attacker.example/fueltypesall.csv")
    }),
    (error) => error instanceof FuelPriceProviderError && error.code === "fuel_price_provider_unavailable"
  );

  resetFuelPriceCacheForTests();
  await assert.rejects(
    getPublicFuelPrice({
      countryCode: "CA",
      regionCode: "ON",
      locality: "Toronto",
      fuelType: "gasoline",
      now: new Date("2026-09-02T12:00:00Z"),
      fetchImpl: async () => officialResponse("http://www.ontario.ca/fueltypesall.csv")
    }),
    (error) => error instanceof FuelPriceProviderError && error.code === "fuel_price_provider_unavailable"
  );
});

test("Ontario official provider maps diesel hybrid to diesel", async () => {
  resetFuelPriceCacheForTests();
  const quote = await getPublicFuelPrice({
    countryCode: "CA",
    regionCode: "ON",
    locality: "Ottawa",
    fuelType: "dieselHybrid",
    now: new Date("2026-09-02T12:00:00Z"),
    fetchImpl: async () => officialResponse()
  });

  assert.equal(quote.pricePerLiter, 1.6);
});

test("provider refuses unsupported countries and stale public data", async () => {
  await assert.rejects(
    getPublicFuelPrice({
      countryCode: "BF",
      regionCode: "KADIOGO",
      locality: "Ouagadougou",
      fuelType: "gasoline"
    }),
    (error) => error instanceof FuelPriceProviderError && error.code === "fuel_price_unavailable"
  );

  resetFuelPriceCacheForTests();
  await assert.rejects(
    getPublicFuelPrice({
      countryCode: "CA",
      regionCode: "ON",
      locality: "Toronto",
      fuelType: "gasoline",
      now: new Date("2026-10-01T12:00:00Z"),
      fetchImpl: async () => officialResponse()
    }),
    (error) => error instanceof FuelPriceProviderError && error.code === "fuel_price_stale"
  );
});

test("Ontario provider reuses its six-hour cache without refetching", async () => {
  resetFuelPriceCacheForTests();
  let fetchCount = 0;
  const fetchImpl = async () => {
    fetchCount += 1;
    return officialResponse();
  };

  const first = await getPublicFuelPrice({
    countryCode: "CA",
    regionCode: "ON",
    locality: "Toronto",
    fuelType: "gasoline",
    now: new Date("2026-09-02T12:00:00Z"),
    fetchImpl
  });
  const second = await getPublicFuelPrice({
    countryCode: "CA",
    regionCode: "ON",
    locality: "Ottawa",
    fuelType: "gasolineHybrid",
    now: new Date("2026-09-02T17:59:59Z"),
    fetchImpl
  });

  assert.equal(fetchCount, 1);
  assert.equal(first.pricePerLiter, 1.55);
  assert.equal(second.pricePerLiter, 1.53);
});

test("Ontario provider coalesces concurrent cache misses into one upstream fetch", async () => {
  resetFuelPriceCacheForTests();
  let fetchCount = 0;
  const fetchImpl = async () => {
    fetchCount += 1;
    await new Promise((resolve) => setTimeout(resolve, 10));
    return officialResponse();
  };
  const input = {
    countryCode: "CA",
    regionCode: "ON",
    locality: "Toronto",
    fuelType: "gasoline",
    now: new Date("2026-09-02T12:00:00Z"),
    fetchImpl
  };

  const [first, second, third] = await Promise.all([
    getPublicFuelPrice(input),
    getPublicFuelPrice(input),
    getPublicFuelPrice(input)
  ]);

  assert.equal(fetchCount, 1);
  assert.equal(first.pricePerLiter, 1.55);
  assert.deepEqual(second, first);
  assert.deepEqual(third, first);
});

test("Ontario provider maps network and invalid source responses to safe errors", async () => {
  resetFuelPriceCacheForTests();
  await assert.rejects(
    getPublicFuelPrice({
      countryCode: "CA",
      regionCode: "ON",
      locality: "Toronto",
      fuelType: "gasoline",
      now: new Date("2026-09-02T12:00:00Z"),
      fetchImpl: async () => {
        throw new TypeError("offline");
      }
    }),
    (error) => error instanceof FuelPriceProviderError &&
      error.code === "fuel_price_provider_unavailable" && error.statusCode === 502
  );

  resetFuelPriceCacheForTests();
  await assert.rejects(
    getPublicFuelPrice({
      countryCode: "CA",
      regionCode: "ON",
      locality: "Toronto",
      fuelType: "gasoline",
      now: new Date("2026-09-02T12:00:00Z"),
      fetchImpl: async () => {
        const response = new Response("upstream failure", { status: 503 });
        Object.defineProperty(response, "url", { value: "https://www.ontario.ca/fuel.csv" });
        return response;
      }
    }),
    (error) => error instanceof FuelPriceProviderError && error.code === "fuel_price_provider_unavailable"
  );
});

test("Ontario provider rejects oversized and malformed CSV payloads", async () => {
  resetFuelPriceCacheForTests();
  await assert.rejects(
    getPublicFuelPrice({
      countryCode: "CA",
      regionCode: "ON",
      locality: "Toronto",
      fuelType: "gasoline",
      now: new Date("2026-09-02T12:00:00Z"),
      fetchImpl: async () => {
        const response = officialResponse();
        response.headers.set("content-length", "2000001");
        return response;
      }
    }),
    (error) => error instanceof FuelPriceProviderError && error.code === "fuel_price_provider_invalid"
  );

  resetFuelPriceCacheForTests();
  await assert.rejects(
    getPublicFuelPrice({
      countryCode: "CA",
      regionCode: "ON",
      locality: "Toronto",
      fuelType: "gasoline",
      now: new Date("2026-09-02T12:00:00Z"),
      fetchImpl: async () => officialResponseWithBody("x".repeat(2_000_001))
    }),
    (error) => error instanceof FuelPriceProviderError && error.code === "fuel_price_provider_invalid"
  );

  resetFuelPriceCacheForTests();
  await assert.rejects(
    getPublicFuelPrice({
      countryCode: "CA",
      regionCode: "ON",
      locality: "Toronto",
      fuelType: "gasoline",
      now: new Date("2026-09-02T12:00:00Z"),
      fetchImpl: async () => {
        const response = new Response("City,Price\nToronto,155.0", { status: 200 });
        Object.defineProperty(response, "url", {
          value: "https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv"
        });
        return response;
      }
    }),
    (error) => error instanceof FuelPriceProviderError && error.code === "fuel_price_provider_invalid"
  );
});

test("Ontario provider uses the provincial average for an unknown locality and rejects future data", async () => {
  resetFuelPriceCacheForTests();
  const quote = await getPublicFuelPrice({
    countryCode: "CA",
    regionCode: "ON",
    locality: "Kingston",
    fuelType: "gasoline",
    now: new Date("2026-09-02T12:00:00Z"),
    fetchImpl: async () => officialResponse()
  });
  assert.equal(quote.locality, "Ontario");
  assert.equal(quote.pricePerLiter, 1.55);

  resetFuelPriceCacheForTests();
  await assert.rejects(
    getPublicFuelPrice({
      countryCode: "CA",
      regionCode: "ON",
      locality: "Toronto",
      fuelType: "gasoline",
      now: new Date("2026-08-29T12:00:00Z"),
      fetchImpl: async () => officialResponse()
    }),
    (error) => error instanceof FuelPriceProviderError && error.code === "fuel_price_stale"
  );
});

test("GET current validates coarse locality and never needs GPS coordinates", async () => {
  let received;
  const app = express();
  app.use("/v1/fuel-prices", createFuelPricesRouter({
    getFuelPrice: async (input) => {
      received = input;
      return { pricePerLiter: 1.55, currency: "CAD" };
    }
  }));
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address();

  try {
    const response = await fetch(
      `http://127.0.0.1:${port}/v1/fuel-prices/current?country=CA&region=ON&locality=Toronto&fuelType=gasoline`
    );
    assert.equal(response.status, 200);
    assert.deepEqual(received, {
      countryCode: "CA",
      regionCode: "ON",
      locality: "Toronto",
      fuelType: "gasoline"
    });

    const invalid = await fetch(
      `http://127.0.0.1:${port}/v1/fuel-prices/current?country=CA&region=ON&locality=${encodeURIComponent("Toronto&latitude=1")}&fuelType=gasoline`
    );
    assert.equal(invalid.status, 400);
  } finally {
    server.close();
  }
});

test("GET current preserves provider errors and hides unexpected failures", async () => {
  const app = express();
  app.use("/v1/fuel-prices", createFuelPricesRouter({
    getFuelPrice: async ({ locality }) => {
      if (locality === "Toronto") {
        throw new FuelPriceProviderError("fuel_price_stale", 503);
      }
      throw new Error("internal details must not leak");
    }
  }));
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address();

  try {
    const stale = await fetch(
      `http://127.0.0.1:${port}/v1/fuel-prices/current?country=CA&region=ON&locality=Toronto&fuelType=gasoline`
    );
    assert.equal(stale.status, 503);
    assert.deepEqual(await stale.json(), { error: "fuel_price_stale" });

    const unexpected = await fetch(
      `http://127.0.0.1:${port}/v1/fuel-prices/current?country=CA&region=ON&locality=Ottawa&fuelType=gasoline`
    );
    assert.equal(unexpected.status, 502);
    assert.deepEqual(await unexpected.json(), { error: "fuel_price_provider_unavailable" });
  } finally {
    server.close();
  }
});
