# Onglet 2 — Votre conduite

**Inspiration BNA** : écrans "Conducteur éclairé" / "Style de conduite" — montagne avec drapeau au sommet, stats 30 jours (53 trajets · 360 km · 9h51m), "Performance globale" avec % badges vs autres conducteurs, "Portrait détaillé" avec barres de progression et curseur "Les autres", "Conseil pratique" en bas.

## 1. Score global — Vue montagne
- Visualisation montagne : position "Vous" (point jaune) vs "Les autres" (moyenne conducteurs Viim à Ouagadougou), sommet 🚩 = conducteur parfait.
- Bandeau stats **30 derniers jours** : Trajets / km / Durée (format BNA exact).
- Performance globale : "Vous avez obtenu X% de tous les badges de conduite. Autres conducteurs : Y%".

## 2. Portrait détaillé — 5 critères *(BNA en a 3 : Vitesse/Fluidité/Vigilance — Viim ajoute Sécurité et Écoconduite)*
Pour chaque critère : gros % coloré, phrase descriptive ("75% de vos trajets sont sans excès de vitesse."), barre de progression colorée, marqueur ▲ "Les autres".

| Critère | Phrase type | Seuils couleur |
|---|---|---|
| 🚀 Vitesse | "% de vos trajets sont sans excès de vitesse" (>80 km/h moto, >100 voiture) | vert >80 / orange 60-80 / rouge <60 |
| 〰 Fluidité | "% de vos freinages et accélérations sont modérés" | vert >75 / orange 50-75 / rouge <50 |
| 📵 Vigilance | "% de vos trajets sont sans distraction" | vert >85 / orange 65-85 / rouge <65 |
| 🛡 Sécurité | Risque global combiné | vert/jaune/orange/rouge |
| 🌿 Écoconduite | "% plus écoénergétique qu'attendu" | vert >10% éco / orange 0-10 / rouge surconso |

- Bouton (i) par critère : explication de la mesure.
- Carte "⭐ Conseil pratique" en bas (style BNA "Restez zen") : générée selon le critère le plus faible.

## 3. Écoconduite — Détail carburant *(BNA : "Consommation d'essence 5-7$ économisé en moyenne" + jauge)*
- Jauge dégradée rouge→vert, position "Vous" vs "Attendue".
- **Économies en FCFA** : "1 200 – 1 800 FCFA économisés ce mois".
- Stats du mois : trajets / km / durée / litres estimés.
- "Le saviez-vous ?" — conseil rotatif.
- **Saisie manuelle du plein** (litres + prix) → recalibrage du modèle conso.

## 4. Historique des trajets *(BNA : "Trajets récents / Voir trajets récents")*
- Filtres : Aujourd'hui / 7 jours / 30 jours / Personnalisé.
- Cartes : miniature + polyline colorée, date/heure/distance/durée, badge score, pictogrammes événements.

## 5. Détail d'un trajet *(BNA : "Mes trajets" — carte plein écran, bulle "6 min · 3 km", "Bilan du trajet" avec 3 pastilles Vitesse/Fluidité/Vigilance, "Vous étiez conducteur · Modifier")*
- Carte MapKit interactive plein écran, polyline colorée par segment, marqueurs événements positionnés.
- Bilan du trajet : pastilles colorées par critère (bleu/gris comme BNA → adapté vert/orange/rouge).
- Stats complètes : distance, durée, vitesse moy/max, score, conso FCFA.
- Liste chronologique des événements avec intensité et position ("Freinage brusque à 14h23").
- "Vous étiez conducteur — Modifier" : requalification conducteur/passager (exclut le trajet du score si passager).
- Conseil personnalisé basé sur les événements du trajet.

## Critères de validation (QA)

- [ ] Polyline fidèle au trajet réel (cible ≥ 95%, minimum 85% — cf. test-plan).
- [ ] Comparaison "Les autres" chargée depuis `/community/averages`, cache 24h, absente si offline et pas de cache.
- [ ] Requalification passager retire le trajet des scores en < 1 s.
- [ ] Saisie de plein modifie la conso estimée des trajets suivants uniquement.
