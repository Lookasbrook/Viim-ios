import {
  createHash,
  createHmac,
  randomBytes,
  timingSafeEqual
} from "node:crypto";

const cookieName = "viim_admin_session";

export function createAdminAuth({
  username,
  password,
  sessionSecret,
  sessionHours = 8,
  secureCookies = true,
  now = () => Date.now()
}) {
  const configured = Boolean(
    username &&
    password?.length >= 12 &&
    sessionSecret?.length >= 32 &&
    Number.isFinite(sessionHours) &&
    sessionHours > 0 &&
    sessionHours <= 24
  );

  function authenticate(candidateUsername, candidatePassword) {
    if (!configured) return false;
    return safeEqual(candidateUsername, username) && safeEqual(candidatePassword, password);
  }

  function createSession() {
    if (!configured) throw new Error("admin_not_configured");
    const expiresAt = now() + sessionHours * 60 * 60 * 1_000;
    const payload = Buffer.from(JSON.stringify({
      subject: username,
      expiresAt,
      nonce: randomBytes(16).toString("base64url")
    })).toString("base64url");
    return `${payload}.${sign(payload, sessionSecret)}`;
  }

  function verifySession(request) {
    if (!configured) return false;
    const token = parseCookies(request.headers.cookie ?? "")[cookieName];
    if (!token) return false;
    const separator = token.lastIndexOf(".");
    if (separator < 1) return false;
    const payload = token.slice(0, separator);
    const signature = token.slice(separator + 1);
    if (!safeEqual(signature, sign(payload, sessionSecret))) return false;

    try {
      const decoded = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
      return decoded.subject === username && Number(decoded.expiresAt) > now();
    } catch {
      return false;
    }
  }

  function sessionCookie(token) {
    const attributes = [
      `${cookieName}=${token}`,
      "HttpOnly",
      "SameSite=Strict",
      "Path=/admin",
      `Max-Age=${Math.round(sessionHours * 60 * 60)}`
    ];
    if (secureCookies) attributes.push("Secure");
    return attributes.join("; ");
  }

  function expiredCookie() {
    const attributes = [
      `${cookieName}=`,
      "HttpOnly",
      "SameSite=Strict",
      "Path=/admin",
      "Max-Age=0"
    ];
    if (secureCookies) attributes.push("Secure");
    return attributes.join("; ");
  }

  return {
    configured,
    authenticate,
    createSession,
    verifySession,
    sessionCookie,
    expiredCookie
  };
}

export function createLoginLimiter({
  maxAttempts = 5,
  windowMs = 15 * 60 * 1_000,
  now = () => Date.now()
} = {}) {
  const attempts = new Map();

  return {
    check(key) {
      const current = attempts.get(key);
      if (!current || current.resetAt <= now()) {
        attempts.delete(key);
        return { allowed: true, retryAfterSeconds: 0 };
      }
      if (current.count < maxAttempts) {
        return { allowed: true, retryAfterSeconds: 0 };
      }
      return {
        allowed: false,
        retryAfterSeconds: Math.max(1, Math.ceil((current.resetAt - now()) / 1_000))
      };
    },
    fail(key) {
      const current = attempts.get(key);
      if (!current || current.resetAt <= now()) {
        attempts.set(key, { count: 1, resetAt: now() + windowMs });
        return;
      }
      current.count += 1;
    },
    succeed(key) {
      attempts.delete(key);
    }
  };
}

function sign(payload, secret) {
  return createHmac("sha256", secret).update(payload).digest("base64url");
}

function safeEqual(left, right) {
  const leftHash = createHash("sha256").update(String(left ?? "")).digest();
  const rightHash = createHash("sha256").update(String(right ?? "")).digest();
  return timingSafeEqual(leftHash, rightHash);
}

function parseCookies(header) {
  return header.split(";").reduce((cookies, part) => {
    const separator = part.indexOf("=");
    if (separator < 1) return cookies;
    const key = part.slice(0, separator).trim();
    const value = part.slice(separator + 1).trim();
    if (key) cookies[key] = value;
    return cookies;
  }, {});
}
