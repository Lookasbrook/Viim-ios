export const config = {
  env: process.env.NODE_ENV ?? "development",
  port: Number(process.env.PORT ?? 3000),
  host: process.env.HOST ?? (process.env.NODE_ENV === "production" ? "0.0.0.0" : "127.0.0.1"),
  databaseUrl: process.env.DATABASE_URL ?? "",
  newagentHealthUrl: process.env.NEWAGENT_HEALTH_URL ?? process.env.NEWAGENT_URL ?? "",
  newagentSendUrl: process.env.NEWAGENT_SEND_URL ?? process.env.NEWAGENT_URL ?? "",
  newagentToken: process.env.NEWAGENT_TOKEN ?? "",
  // Webhook WhatsApp entrant (STOP + statuts de livraison).
  whatsappVerifyToken: process.env.WHATSAPP_VERIFY_TOKEN ?? "",
  whatsappAppSecret: process.env.WHATSAPP_APP_SECRET ?? "",
  whatsappWebhookSharedToken: process.env.WHATSAPP_WEBHOOK_SHARED_TOKEN ?? "",
  // Quand true, une alerte est refusée (422) si le conducteur n'a pas attesté le consentement
  // de ses contacts. Laisser false tant que l'app iOS n'envoie pas encore l'attestation.
  requireContactsConsent: (process.env.REQUIRE_CONTACTS_CONSENT ?? "false") === "true",
  publicBaseUrl: process.env.PUBLIC_BASE_URL ?? "https://api.burktech-ia.com",
  apnsTeamId: process.env.APNS_TEAM_ID ?? "",
  apnsKeyId: process.env.APNS_KEY_ID ?? "",
  apnsBundleId: process.env.APNS_BUNDLE_ID ?? "com.yamstack.viim",
  apnsPrivateKey: process.env.APNS_PRIVATE_KEY ?? "",
  adminUsername: process.env.ADMIN_USERNAME ?? "",
  adminPassword: process.env.ADMIN_PASSWORD ?? "",
  adminSessionSecret: process.env.ADMIN_SESSION_SECRET ?? "",
  adminSessionHours: Number(process.env.ADMIN_SESSION_HOURS ?? 8),
  version: process.env.npm_package_version ?? "0.1.0"
};

export function requireProductionDependency(value) {
  return config.env === "production" ? Boolean(value) : true;
}
