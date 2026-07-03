# Backend — Résumé journalier WhatsApp

Chaque soir à **20h00 (UTC+0, heure Ouagadougou)**, le backend envoie via **NEwAGENT-IA** un résumé à chaque utilisateur ayant conduit dans la journée. Aucun envoi si 0 trajet.

## Template du message

```
📊 Ton résumé Viim — [Date]

🗺 Trajets : [nb]  |  📏 Distance : [X] km  |  ⏱ Durée : [X]h[X]m
⭐ Score du jour : [X]/100  |  ⛽ Conso estimée : [X]L (~[X] FCFA)

⚡ Événements : [X] freinages brusques · [X] accélérations brusques

[MESSAGE PERSONNALISÉ SELON SCORE]

— Viim 🛡  |  Répondre STOP pour désactiver
```

## Message personnalisé selon score

| Score | Message |
|---|---|
| > 85 | "Excellente journée ! Tu es dans le top 20% aujourd'hui. 🏆" |
| 65-85 | "Bonne conduite globale. Attention aux freinages brusques." |
| < 65 | "Ta conduite présente des risques. Prends soin de toi. 🛡" |

## Règles

- Source : table `daily_summaries` (uniquement les jours avec `tripsCount > 0`).
- Pendant la calibration : message sans score ("Calibration en cours — [X] trajets restants").
- Réponse **STOP** → `users.dailySummaryOptOut = true` (réactivable dans Paramètres).
- Si NEwAGENT-IA down à 20h00 : retry à 20h15 et 20h30, puis abandon (pas de SMS pour le résumé — le fallback SMS est réservé aux urgences).

## Critères de validation (QA)

- [ ] Message reçu entre 20h00 et 20h05 pour un utilisateur ayant conduit.
- [ ] Aucun message si 0 trajet dans la journée.
- [ ] STOP désactive dès le lendemain ; réactivation possible depuis l'app.
- [ ] Taux de réception ≥ 90% (cible 99%) — cf. test-plan.
