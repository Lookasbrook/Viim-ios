# ADR — Résoudre la motorisation sans l'inférer des capteurs

- Date : 2026-08-11
- Statut : accepté
- Décideur : Guy / Codex builder

## Contexte

Marque, modèle et année ne désignent pas toujours une motorisation unique. Des
versions essence, diesel, hybrides, plusieurs puissances et transmissions peuvent
partager ces trois champs. Les accélérations observées par le téléphone sont
également influencées par la pente, le trafic, la charge et le conducteur.

Deviner une version plausible ferait ensuite choisir une consommation, un PCI
et un prix qui pourraient tous être faux sans signal visible pour l'utilisateur.

## Décision

1. Le profil véhicule collecte le type de carburant comme donnée du véhicule,
   sans demander prix, consommation, plein ou correction de trajet.
2. Une fiche unique après filtrage peut alimenter le modèle.
3. Plusieurs fiches plausibles produisent une fourchette calculée sur toutes les
   versions retenues, avec leurs identifiants et sources.
4. Une fourchette dépassant le seuil mesuré en Phase 3 produit `unavailable`.
5. Aucun signal GPS ou inertiel ne sert à inférer la motorisation.
6. Les profils historiques sans type de carburant restent valides ; leur coût
   est `pending` ou `unavailable` tant que la résolution n'est pas probante.

## Conséquences

- La couverture sera inférieure à 100 %, volontairement.
- La question carburant doit être ajoutée lors d'une phase ultérieure avec une
  migration non bloquante ; cette ADR ne modifie pas encore l'onboarding.
- Les hybrides et véhicules électriques restent hors périmètre v1.
- Le seuil maximal de largeur de fourchette sera fixé sur les données réelles,
  jamais choisi pour atteindre artificiellement un taux de couverture.
- Chaque résultat conserve les identifiants des fiches candidates, la décision
  de résolution et sa version afin de rester auditable.
