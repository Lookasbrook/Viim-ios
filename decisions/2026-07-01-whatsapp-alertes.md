# ADR — WhatsApp comme canal d'alerte primaire, SMS en fallback

**Date** : 2026-07-01 · **Statut** : Accepté

## Contexte
En cas de collision, il faut joindre les proches de façon fiable. Au Burkina Faso, WhatsApp est le canal de communication dominant ; les push d'apps tierces sont peu fiables et peu consultés.

## Décision
Alertes envoyées par **WhatsApp Business API via NEwAGENT-IA** (déjà déployé et opérationnel sur le VPS Hetzner), avec **SMS natif iOS (MessageUI) en fallback** si le backend est injoignable (pas de data, 503).

## Justification
NEwAGENT-IA existe déjà — coût marginal nul. WhatsApp permet position, texte riche et accusés de lecture (qui déclenchent la cascade contact 2 après 5 min de non-lecture). Le SMS fonctionne sans data — indispensable en zone à couverture faible.

## Conséquences
- Le numéro de téléphone (E.164) est l'identifiant central de l'utilisateur et de ses contacts.
- Dépendance à la disponibilité de NEwAGENT-IA → monitoring `/health` inclut son statut ; taux de réception mesuré dans le test-plan (min 90%).
- Le résumé journalier n'a PAS de fallback SMS (réservé aux urgences, coût).
