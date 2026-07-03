const sensitiveKeys = new Set([
  "medical",
  "contacts",
  "phone",
  "phoneE164",
  "NEWAGENT_TOKEN",
  "JWT_SECRET"
]);

export function scrub(value) {
  if (Array.isArray(value)) {
    return value.map(scrub);
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [
        key,
        sensitiveKeys.has(key) ? "[redacted]" : scrub(nested)
      ])
    );
  }

  return value;
}

export function logScrubber(_request, _response, next) {
  next();
}
