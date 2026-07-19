# Onglet 1 — Accueil

**Inspiration BNA** : écran d'accueil "Bonjour Guy" — salutation centrée, carte d'actions rapides, section "Ce qui est couvert", cartes de navigation vers les sections. Adaptation Viim ci-dessous.

## Structure de l'écran (haut → bas)

### 1. En-tête personnalisé
- Logo "Viim." discret, "Bonjour / Bonsoir [Prénom]" selon l'heure, date du jour en sous-titre.
- Cloche de notifications avec badge si non-lues ; avatar/initiales → Profil.

### 1bis. Carte véhicule suivi *(équivalent "Ce qui est couvert — TOYOTA COROLLA LE 4P · ✓ Couvert" avec photo du véhicule, BNA)*
- Illustration ou photo du véhicule inscrit (cf. [inscription-onboarding.md](inscription-onboarding.md)) + "MARQUE MODÈLE", année, badge "✓ Suivi actif".
- Tap → Profil véhicule (changement, photo, entretien).

### 2. Carte résumé du jour *(équivalent de la barre d'actions rapides BNA)*
Mise à jour en temps réel dès la fin d'un trajet :
- 📏 km parcourus · ⭐ score du jour (0-100, coloré vert/orange/rouge) · ⛽ coût carburant en FCFA seulement si conso/prix carburant sont renseignés · 🕐 temps de conduite · 🏍 nombre de trajets.
- Pendant la calibration : "Calibration en cours (trajet X/5)" à la place du score.

### 3. Statut des fonctions actives *(équivalent des pastilles "Activé/Désactivé" BNA, ex. "Soutien en temps réel : Activé")*
- 🟢/🔴 Détection de trajet — toggle rapide.
- 🟢/🔴 Détection collision — pastille colorée.
- 🟢 Alertes famille — nombre de contacts configurés (alerte visuelle si 0).
- 🟢/🔴 Connexion réseau — "En ligne" / "Hors ligne — X trajets en attente de sync".

### 4. Trajets récents *(équivalent "Trajets récents" BNA : carte miniature + date + heure + km + 3 icônes d'événements)*
- Max 3 trajets, lien "Voir tous" → onglet Votre conduite.
- Chaque carte : miniature MapKit avec polyline colorée selon score, "1 juillet · 21h42 · 2 km", badge score, pictogrammes événements (freinage/accélération/distraction), badge rôle "Conducteur/Passager".

## Critères de validation (QA)

- [ ] Le résumé se met à jour < 5 s après la fin d'un trajet, sans réseau.
- [ ] Les toggles reflètent l'état réel des services (pas d'état fantôme après kill de l'app).
- [ ] Hors ligne : compteur de trajets en attente exact ; disparaît après sync.
- [ ] Aucun score visible pendant les 5 trajets de calibration.
