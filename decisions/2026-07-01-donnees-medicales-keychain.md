# ADR — Données médicales : Keychain uniquement, jamais en base

**Date** : 2026-07-01 · **Statut** : Accepté

## Contexte
La fiche médicale (groupe sanguin, allergies, maladies, CNIB) est la donnée la plus sensible de l'app. Elle doit pourtant atteindre les secours en cas d'accident.

## Décision
Stockage **exclusivement dans le Keychain iOS (AES-256)**. Jamais transmise au backend en routine, jamais persistée en PostgreSQL. Transmission uniquement dans le payload d'alerte collision confirmée (pas de réponse sous 60 s, ou "J'AI BESOIN D'AIDE"), relayée au contact WhatsApp puis **non conservée** côté serveur.

## Justification
Minimisation des données : une fuite backend ne peut pas exposer de données médicales. Confiance utilisateur (mention visible dans l'UI). Conformité au principe de proportionnalité.

## Conséquences
- Pas de restauration de la fiche médicale en cas de changement de téléphone — l'utilisateur la ressaisit (acceptable, < 2 min).
- Le endpoint `/alerts/collision` doit traiter le payload médical en mémoire uniquement (log scrubbing obligatoire côté Node.js).
- QA : vérification par proxy qu'aucun champ médical ne transite hors collision (test-plan S2, critère onglet-3).
