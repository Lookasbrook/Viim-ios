const ONTARIO_SOURCE_URL = new URL("https://www.ontario.ca/v1/files/fuel-prices/fueltypesall.csv");
const ALLOWED_SOURCE_HOSTS = new Set([
  "ontario.ca",
  "www.ontario.ca",
  // Hôte de stockage exact vers lequel l'URL officielle ontario.ca redirige.
  "prod-energy-fuel-prices.s3.amazonaws.com"
]);
const MAX_RESPONSE_BYTES = 2_000_000;
const CACHE_TTL_MS = 6 * 60 * 60 * 1_000;
const MAX_SOURCE_AGE_MS = 14 * 24 * 60 * 60 * 1_000;

let cachedOntarioDataset = null;
let pendingOntarioDatasetLoad = null;

export class FuelPriceProviderError extends Error {
  constructor(code, statusCode) {
    super(code);
    this.code = code;
    this.statusCode = statusCode;
  }
}

export async function getPublicFuelPrice({
  countryCode,
  regionCode,
  locality,
  fuelType,
  fetchImpl = fetch,
  now = new Date()
}) {
  const country = countryCode.trim().toUpperCase();
  const region = regionCode.trim().toUpperCase();

  // Seul un jeu de donnees gouvernemental, date et exploitable est active.
  // Les autres pays restent explicitement indisponibles plutot que de recevoir
  // un prix approximatif ou collecte sur un site non contractuel.
  if (country !== "CA" || !["ON", "ONTARIO"].includes(region)) {
    throw new FuelPriceProviderError("fuel_price_unavailable", 404);
  }

  const providerFuelType = normalizedProviderFuelType(fuelType);
  if (!providerFuelType) {
    throw new FuelPriceProviderError("fuel_price_unavailable", 404);
  }

  const dataset = await loadOntarioDataset({ fetchImpl, now });
  const row = dataset.latestByFuelType.get(providerFuelType);
  if (!row) {
    throw new FuelPriceProviderError("fuel_price_unavailable", 404);
  }

  const observedAt = parseSourceDate(row.Date);
  const ageMs = now.getTime() - observedAt.getTime();
  if (ageMs < -24 * 60 * 60 * 1_000 || ageMs > MAX_SOURCE_AGE_MS) {
    throw new FuelPriceProviderError("fuel_price_stale", 503);
  }

  const selection = selectOntarioPrice(row, locality);
  if (!selection || !Number.isFinite(selection.centsPerLiter) || selection.centsPerLiter <= 0) {
    throw new FuelPriceProviderError("fuel_price_unavailable", 404);
  }

  return {
    countryCode: "CA",
    regionCode: "ON",
    locality: selection.locality,
    fuelType,
    // Le jeu de données est en cents/L avec un dixième de cent : conserver
    // exactement trois décimales évite les artefacts IEEE-754 dans l'API JSON.
    pricePerLiter: Math.round(selection.centsPerLiter * 10) / 1_000,
    currency: "CAD",
    observedAt: observedAt.toISOString(),
    retrievedAt: now.toISOString(),
    source: "government_of_ontario_fuel_price_survey",
    sourceUrl: ONTARIO_SOURCE_URL.toString()
  };
}

async function loadOntarioDataset({ fetchImpl, now }) {
  if (cachedOntarioDataset && now.getTime() - cachedOntarioDataset.loadedAt < CACHE_TTL_MS) {
    return cachedOntarioDataset;
  }

  // Coalescer les appels concurrents au renouvellement du cache. Sans ce
  // single-flight, une rafale sur la route publique telechargerait le meme
  // fichier officiel autant de fois avant que le premier appel ne termine.
  if (pendingOntarioDatasetLoad) {
    return pendingOntarioDatasetLoad;
  }

  pendingOntarioDatasetLoad = fetchOntarioDataset({ fetchImpl, now });
  try {
    return await pendingOntarioDatasetLoad;
  } finally {
    pendingOntarioDatasetLoad = null;
  }
}

async function fetchOntarioDataset({ fetchImpl, now }) {

  let response;
  try {
    response = await fetchImpl(ONTARIO_SOURCE_URL, {
      headers: { Accept: "text/csv" },
      redirect: "follow",
      signal: AbortSignal.timeout(8_000)
    });
  } catch {
    throw new FuelPriceProviderError("fuel_price_provider_unavailable", 502);
  }

  let finalURL;
  try {
    finalURL = new URL(response.url);
  } catch {
    throw new FuelPriceProviderError("fuel_price_provider_unavailable", 502);
  }

  if (!response.ok ||
      finalURL.protocol !== "https:" ||
      !ALLOWED_SOURCE_HOSTS.has(finalURL.hostname)) {
    throw new FuelPriceProviderError("fuel_price_provider_unavailable", 502);
  }

  const declaredLength = Number(response.headers.get("content-length") ?? 0);
  if (declaredLength > MAX_RESPONSE_BYTES) {
    throw new FuelPriceProviderError("fuel_price_provider_invalid", 502);
  }

  const text = await readBoundedText(response);

  const rows = parseCSV(text);
  const latestByFuelType = new Map();
  for (const row of rows) {
    const fuel = row["Fuel Type"];
    if (!fuel || !row.Date) continue;
    const existing = latestByFuelType.get(fuel);
    if (!existing || row.Date > existing.Date) {
      latestByFuelType.set(fuel, row);
    }
  }

  if (latestByFuelType.size === 0) {
    throw new FuelPriceProviderError("fuel_price_provider_invalid", 502);
  }

  cachedOntarioDataset = { loadedAt: now.getTime(), latestByFuelType };
  return cachedOntarioDataset;
}

async function readBoundedText(response) {
  const reader = response.body?.getReader?.();
  if (!reader) {
    throw new FuelPriceProviderError("fuel_price_provider_invalid", 502);
  }

  const chunks = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const chunk = Buffer.from(value);
      totalBytes += chunk.byteLength;
      if (totalBytes > MAX_RESPONSE_BYTES) {
        await reader.cancel();
        throw new FuelPriceProviderError("fuel_price_provider_invalid", 502);
      }
      chunks.push(chunk);
    }
  } catch (error) {
    if (error instanceof FuelPriceProviderError) throw error;
    throw new FuelPriceProviderError("fuel_price_provider_unavailable", 502);
  }
  return Buffer.concat(chunks, totalBytes).toString("utf8");
}

function normalizedProviderFuelType(fuelType) {
  switch (fuelType) {
    case "gasoline":
    case "gasolineHybrid":
      return "Regular Unleaded Gasoline";
    case "diesel":
    case "dieselHybrid":
      return "Diesel";
    default:
      return null;
  }
}

function selectOntarioPrice(row, locality) {
  const normalized = normalize(locality);
  const cityColumns = [
    [["ottawa"], ["Ottawa"]],
    [["toronto"], ["Toronto West/Ouest", "Toronto East/Est"]],
    [["windsor"], ["Windsor"]],
    [["london"], ["London"]],
    [["peterborough"], ["Peterborough"]],
    [["stcatharines", "saintcatharines"], ["St. Catharine's"]],
    [["sudbury", "greatersudbury"], ["Sudbury"]],
    [["saultstemarie", "saultsaintemarie"], ["Sault Saint Marie"]],
    [["thunderbay"], ["Thunder Bay"]],
    [["northbay"], ["North Bay"]],
    [["timmins"], ["Timmins"]],
    [["kenora"], ["Kenora"]],
    [["parrysound"], ["Parry Sound"]]
  ];

  const match = cityColumns.find(([aliases]) => aliases.some((alias) => normalized.includes(alias)));
  const columns = match?.[1] ?? ["Ontario Average/Moyenne provinciale"];
  const values = columns
    .map((column) => Number(row[column]))
    .filter((value) => Number.isFinite(value) && value > 0);
  if (values.length === 0) return null;

  return {
    locality: match ? locality.trim() : "Ontario",
    centsPerLiter: values.reduce((sum, value) => sum + value, 0) / values.length
  };
}

function normalize(value) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

function parseSourceDate(value) {
  const date = new Date(`${value}T00:00:00.000Z`);
  if (!Number.isFinite(date.getTime())) {
    throw new FuelPriceProviderError("fuel_price_provider_invalid", 502);
  }
  return date;
}

function parseCSV(text) {
  const records = [];
  let record = [];
  let field = "";
  let quoted = false;

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (character === '"') {
      if (quoted && text[index + 1] === '"') {
        field += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === "," && !quoted) {
      record.push(field.trim());
      field = "";
    } else if ((character === "\n" || character === "\r") && !quoted) {
      if (character === "\r" && text[index + 1] === "\n") index += 1;
      record.push(field.trim());
      if (record.some(Boolean)) records.push(record);
      record = [];
      field = "";
    } else {
      field += character;
    }
  }
  if (field || record.length) {
    record.push(field.trim());
    records.push(record);
  }

  const [headers, ...values] = records;
  if (!headers?.includes("Date") || !headers.includes("Fuel Type")) {
    throw new FuelPriceProviderError("fuel_price_provider_invalid", 502);
  }
  return values.map((fields) => Object.fromEntries(headers.map((header, index) => [header, fields[index] ?? ""])));
}

export function resetFuelPriceCacheForTests() {
  cachedOntarioDataset = null;
  pendingOntarioDatasetLoad = null;
}
