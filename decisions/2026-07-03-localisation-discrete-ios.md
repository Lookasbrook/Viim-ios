# ADR — Localisation iOS discrète par défaut

- Date : 2026-07-03
- Statut : Acceptée
- Contexte : après l'autorisation de localisation, iOS affichait un indicateur GPS visible en haut de l'écran. Le comportement venait du démarrage automatique du suivi continu après onboarding, de la demande automatique `Always` et de `showsBackgroundLocationIndicator=true`.

## Décision

Viim ne démarre plus le flux GPS continu au simple lancement de l'app après onboarding.

- L'app demande uniquement l'autorisation `When In Use` quand c'est nécessaire.
- La permission `Always` n'est plus demandée automatiquement.
- L'indicateur arrière-plan iOS est désactivé par défaut.
- Les mises à jour GPS continues et les changements significatifs ne sont lancés que par `startMonitoring()`.
- Les changements significatifs ne sont activés que si l'utilisateur a déjà accordé `Always`.

## Conséquences

- L'utilisateur ne voit plus un mode GPS persistant après avoir seulement autorisé la localisation.
- Le suivi de trajet automatique écran verrouillé reste à traiter avec un consentement explicite et une stratégie de déclenchement discrète, idéalement basée sur CoreMotion puis confirmation GPS.
- Le scénario QA S1 écran verrouillé doit être rejoué après l'ajout de ce flux explicite.
