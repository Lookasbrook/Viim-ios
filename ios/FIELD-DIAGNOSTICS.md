# Diagnostic terrain — collecte de trajets iOS

Quand un utilisateur signale « l'app ne collecte plus rien », l'état réel ne se
lit que sur l'appareil. Ne pas deviner : tirer `ViimDiagnostics.log`.

## Tirer le journal depuis un iPhone branché (30 s)

```bash
# UDID de l'appareil
xcrun devicectl list devices

DEV=<UDID>
xcrun devicectl device copy from --device "$DEV" \
  --domain-type appDataContainer --domain-identifier com.yamstack.viim \
  --source "Library/Application Support/ViimDiagnostics.log" \
  --destination ./ViimDiagnostics.log
```

Le même dossier contient `ViimCollectionHealth.json` (journal de santé, 7 j,
sans PII) — le tirer pareillement au besoin.

## Lire le journal

Une ligne par lancement dit si la capture écran verrouillé est possible :

```bash
grep -E "app\.launch|carburant\.featureFlags|location\.readiness" ViimDiagnostics.log | tail -20
```

- `auth=authorizedAlways state=ready` → collecte arrière-plan OK.
- `auth=authorizedWhenInUse state=foregroundOnly` → **permission iOS retombée
  à « Lorsque l'app est active »**. Aucun trajet hors premier plan. Correctif =
  action utilisateur : Réglages iOS → Viim → Localisation → « Toujours ». Aucun
  code ne peut l'accorder ; `requestAlwaysAuthorization()` est déjà appelé au
  premier plan mais iOS ne re-présente pas le prompt après le premier refus.
- `backgroundRefresh=denied|restricted` → Actualisation en arrière-plan coupée
  ou Mode économie d'énergie actif.
- `gpsSessionSplit=true` → ne devrait plus jamais arriver (flag debug purgé au
  lancement, `CarburantFeatureFlags.clearPersistedDebugOverrides()`).

```bash
# Trajets enregistrés et rejets
grep -E "trip\.persisted|trip\.capture\.outcome" ViimDiagnostics.log | tail -40
```

## Signal in-app

`CollectionHealthSnapshot.isBackgroundCaptureStalled` devient vrai quand un
blocage de réglage système coexiste avec ≥ 2 jours distincts de conduite dans
la fenêtre de 7 j. L'écran d'accueil affiche alors une bannière rouge non
masquable (`CollectionStalledBanner`) qui ouvre les Réglages iOS. C'est le
garde-fou de l'incident 2026-08-20 (permission retombée à When In Use, ~3
semaines sans trajet et aucune alerte forte).
