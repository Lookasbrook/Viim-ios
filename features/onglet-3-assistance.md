# Onglet 3 — Assistance

**Inspiration BNA** : écran Assistance — "Soumettre une réclamation" / "Obtenir de l'assistance routière" en haut, carte "Soutien en temps réel : Activé 🟢", "Voir ma localisation", "Me faire remorquer", "Remplir un constat d'accident", numéro 24/7 en bas. Adapté aux réalités burkinabè (WhatsApp, 18/17, hôpitaux).

## 1. Détection de collision *(BNA : "Soutien en temps réel — Vous recevrez du soutien dès qu'une collision est détectée · Activé 🟢")*
- Toggle ON/OFF — **activé par défaut** à l'inscription. Badge "Soutien en temps réel : Activé" visible en haut de l'onglet.
- Sensibilité configurable : Faible / Normale / Élevée (selon qualité des routes).
- Fenêtre d'annulation **60 s** : notification locale "Êtes-vous en sécurité ? [OUI] [J'AI BESOIN D'AIDE]".
- Position GPS + 30 s de données pré-impact conservées. Pipeline complet : [sensor-algorithms.md §5](../architecture/sensor-algorithms.md).

## 2. Alerte famille — Contacts d'urgence
- Jusqu'à 3 contacts WhatsApp ordonnés : contact 1 prioritaire → contact 2 si message non lu sous 5 min → contact 3 backup.
- Message personnalisé optionnel.
- Bouton **"Envoyer un test"** (`POST /alerts/test`) — vérifie la chaîne complète NEwAGENT-IA.
- SMS fallback automatique (MessageUI) si WhatsApp échoue ou pas de data.

## 3. Fiche médicale d'urgence
- Groupe sanguin, allergies, maladies chroniques, médicaments (200 car. max), numéro CNIB.
- **Keychain AES-256 uniquement** — mention visible : "Ces données ne quittent jamais votre téléphone sauf en cas d'accident confirmé". Voir [ADR](../decisions/2026-07-01-donnees-medicales-keychain.md).
- Statut "Complète / Incomplète" affiché dans le profil.

## 4. Voir ma localisation *(BNA : "Localisation actuelle estimée — Rue Baudrier, Québec · Coordonnées GPS 46.9064, -71.2115 · Partager ma localisation" + carte)*
- Carte centrée temps réel + adresse approximative + coordonnées GPS affichées en clair.
- Bouton "Partager ma position maintenant" → WhatsApp vers contact choisi.
- Copier les coordonnées ; lien Google Maps direct.

## 5. Constat d'accident numérique *(BNA : "Remplir un constat d'accident")*
- Date/heure et lieu pré-remplis si collision détectée.
- Véhicules impliqués (plaque, modèle, assurance), photos via caméra, description libre.
- **Export PDF** mis en forme, prêt pour l'assureur.

## 6. Assistance routière *(BNA : "Me faire remorquer" + "Besoin d'aide ? Appelez notre service 24/7 : 1.877.392.6393")*
- 🚒 Sapeurs-pompiers **18** et 👮 Police **17** — un tap pour appeler (gros boutons, style numéro 24/7 BNA).
- 📞 Dépanneurs locaux Ouagadougou (liste pré-intégrée) + partage automatique de position par WhatsApp/SMS.
- 🏥 Hôpitaux et cliniques les plus proches (MapKit, tri par distance).

## Critères de validation (QA)

- [ ] Collision simulée → alerte WhatsApp reçue par contact 1 en < 90 s après la fenêtre de 60 s.
- [ ] Cascade contact 2 déclenchée si non-lu 5 min ; SMS fallback si 503 backend.
- [ ] Faux positifs < 10% (cible < 3%) sur routes dégradées — cf. test-plan.
- [ ] Fiche médicale absente de tout payload réseau hors collision confirmée (vérification proxy).
- [ ] Micro-sync collision survit à l'app tuée (URLSession background).
- [ ] Appels 18/17 fonctionnels en un tap depuis l'écran verrouillé post-collision (notification).
