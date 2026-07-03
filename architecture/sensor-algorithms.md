# Algorithmes capteurs — Filtrage, détection d'événements, score

C'est le cœur technique du MVP. La phase de test valide exclusivement ce document.

## 1. Filtrage de l'accéléromètre

Routes dégradées + vibrations moto = données très bruitées. Filtre passe-bas obligatoire :

```
filtered[n] = alpha * raw[n] + (1 - alpha) * filtered[n-1]
```

| Véhicule | alpha | Justification |
|---|---|---|
| Moto | 0.15 | Vibrations fortes, filtrage agressif |
| Voiture | 0.25 | Bruit modéré |
| Vélo | 0.20 | Intermédiaire |

Le type de véhicule vient du profil utilisateur et ajuste alpha ET les seuils d'événements.

## 2. Confirmation GPS (anti-faux-positifs)

**Règle absolue** : aucun événement accéléromètre n'est comptabilisé sans confirmation GPS.

Un freinage/accélération brusque détecté par l'accéléromètre n'est validé que si la vitesse GPS confirme une variation **> 5 km/h dans la même fenêtre de 2 secondes**. Sinon, l'événement est rejeté (nid-de-poule, vibration, téléphone manipulé).

## 3. Détection d'événements

| Événement | Signal accéléromètre (filtré) | Confirmation GPS | Fenêtre |
|---|---|---|---|
| Freinage brusque | Décélération longitudinale > seuil (calibré) | Δv > 5 km/h en baisse | 2 s |
| Accélération brusque | Accélération longitudinale > seuil | Δv > 5 km/h en hausse | 2 s |
| Virage serré | Accélération latérale > seuil | Vitesse > 15 km/h | 2 s |
| Excès de vitesse | — | > 80 km/h (moto) / > 100 km/h (voiture) soutenu 10 s | 10 s |
| Distraction | Manipulation écran (`UIScreen`/interactions) pendant que vitesse GPS > 10 km/h | vitesse > 10 km/h | — |
| **Collision** | Pic > seuil élevé (sensibilité Faible/Normale/Élevée) suivi d'une vitesse GPS ≈ 0 | arrêt confirmé | 5 s |

Les seuils numériques exacts sont fixés pendant la calibration terrain (phase MVP) et documentés dans `qa/test-results.md` au fur et à mesure.

## 4. Phase de calibration silencieuse

- Les **5 premiers trajets** de chaque utilisateur établissent son bruit de fond (percentiles de l'accélération filtrée par type de route).
- **Aucun score affiché** pendant cette phase — l'UI montre "Calibration en cours (trajet X/5)".
- Données envoyées au backend avec `calibration: true` — exclues des moyennes communautaires.

## 5. Détection de collision — pipeline complet

```
Pic accéléromètre > seuil ──► Vitesse GPS chute vers ~0 ──► Notification locale
                                                             "Êtes-vous en sécurité ?"
                                                             [OUI] [J'AI BESOIN D'AIDE]
                                                                    │
                              ┌─────────────────────────────────────┤
                              │ OUI sous 60 s                       │ Pas de réponse 60 s
                              ▼                                     ▼   ou "BESOIN D'AIDE"
                         Annulation,                     Micro-sync collision (background
                         événement loggé                 URLSession) : position GPS,
                                                         30 s de données pré-impact,
                                                         fiche médicale (Keychain → payload)
                                                                    │
                                                         Backend ──► WhatsApp contact 1
                                                         (contact 2 si non-lu sous 5 min,
                                                          puis contact 3) + SMS fallback
```

Le buffer circulaire de 30 secondes de données capteurs pré-impact est conservé en mémoire pendant tout trajet.

## 6. Score de conduite (0-100)

### Portrait détaillé — 5 critères (modèle BNA adapté)

| Critère | Mesure | Vert | Orange | Rouge |
|---|---|---|---|---|
| Vitesse | % trajets sans excès | >80% | 60-80% | <60% |
| Fluidité | % freinages/accélérations modérés | >75% | 50-75% | <50% |
| Vigilance | % trajets sans distraction | >85% | 65-85% | <65% |
| Sécurité | Risque global combiné (3 critères ci-dessus) | Vert/Jaune/Orange/Rouge | | |
| Écoconduite | Efficacité vs conduite de référence | économies >10% | 0-10% | surconso |

Chaque critère est comparé à la **moyenne des conducteurs Viim à Ouagadougou** (curseur "Les autres" sous la barre, comme dans l'app BNA).

### Score global

Pondération initiale (à valider en phase de test) : Vitesse 25% · Fluidité 25% · Vigilance 25% · Sécurité dérivée · Écoconduite 25%. Le score du trajet colore la polyline (vert ≥ 80, orange 60-79, rouge < 60).

### Estimation carburant

Modèle simple : conso de référence du véhicule (saisie profil) modulée par les événements (accélérations brusques, vitesse). Recalibrage par **saisie manuelle du plein** (litres + prix payé) → conversion FCFA affichée partout.

## 7. Économie de batterie

- Précision GPS : 5 m par défaut → 20 m en mode économie.
- Fréquence accéléromètre : 50 Hz en trajet, capteurs coupés hors trajet.
- Détection automatique début/fin de trajet : vitesse GPS soutenue > 10 km/h pendant 30 s (début) ; arrêt > 5 min (fin).
