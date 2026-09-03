# Blueprint — Carburant modélisé, transport collectif, indicateur GPS

Date : 2026-08-11
Statut : à critiquer puis exécuter
Prévaut sur : `2026-07-14-fiabilite-vehicules-couts-internationalisation.md` pour les sections carburant et indicateur GPS
Marchés : Burkina Faso, Canada (extensible UE / USA)

---

## 0. À lire avant de coder

Ce document te demande de **critiquer avant d'exécuter**. La §13 liste les points où je peux me tromper : traite-les en premier, tranche-les avec la documentation Apple courante et le code réel, et remonte tout désaccord **avant** la première ligne de code. Un blueprint exécuté sans critique sur des fondations fausses coûte plus cher qu'un aller-retour.

Trois exigences produit non négociables encadrent tout le reste :

1. **L'utilisateur ne saisit rien.** Ni prix du carburant, ni consommation, ni plein, ni correction de trajet. Marque / modèle / année sont déjà collectés à l'inscription et suffisent.
2. **Tout chiffre affiché doit être traçable à une source.** Référentiel officiel, fiche technique publique, homologation certifiée, ou mesure capteur du trajet. Aucune constante inventée.
3. **Aucune régression sur la capture des trajets.** L'incident du 18 juillet (trajets tronqués) est la contrainte dure de ce blueprint. Tout ce qui touche à `LocationService` doit passer la validation terrain de non-régression (§11.4) avant d'être considéré comme fait.

---

## 1. Résultat attendu

Viim produit un coût de carburant **modélisé à partir de la physique du trajet réellement mesuré** et valorisé par un **prix officiel daté**, sans aucune saisie utilisateur.

```
AVANT   litres = km × constante_catalogue          ← ne réagit à rien
        coût   = litres × prix_tapé_par_l'utilisateur   ← invérifiable

APRÈS   litres = ∫ modèle_physique(v, a, pente, ρ_air, Crr, fiche_technique) dt
        coût   = litres × prix_officiel_en_vigueur_à_la_date_du_trajet
```

En parallèle :

- les déplacements en transport collectif sont **classés** et exclus du carburant et des scores conducteur, au lieu d'être supprimés en silence ;
- l'indicateur de localisation iOS **disparaît hors conduite** et n'apparaît que pendant un trajet actif.

---

## 2. Position par rapport aux blueprints existants — conflit à résoudre

Il existe une **contradiction documentée** dans le repo que ce blueprint doit trancher.

**Exigence A** — `blueprints/2026-07-14-…md` §2.2 :
> « invalider toute session dès l'arrêt du suivi ; ne jamais afficher durablement l'indicateur lorsque l'utilisateur ne conduit pas. »

**Exigence B** — correctif du 18 juillet, inscrit en commentaire dans `ios/Viim/Services/LocationService.swift:196-205` et `:372-377` :
> « en Always, la session doit rester active même pendant l'idle — elle doit exister au moment où iOS termine le processus pour que sa recréation immédiate au relancement rétablisse la cadence GPS continue. »

Le code applique **B**. L'utilisateur constate le symptôme de B : indicateur permanent tant que l'app n'est pas tuée. Le blueprint du 14/07 exigeait A, mais B lui est postérieur et corrigeait une perte de données réelle.

**Décision de ce blueprint : A et B sont conciliables, via deux sessions distinctes.** Le code lui-même en porte déjà l'hypothèse (`LocationService.swift:208-212`) :

| Session | Rôle | Indicateur |
|---|---|---|
| `CLBackgroundActivitySession` (iOS 17+) | autorise la localisation continue en arrière-plan | **affiché** — c'est sa fonction |
| `CLServiceSession(authorization: .always)` (iOS 18+) | déclare l'exploitation de l'autorisation Always | **non affiché** (à vérifier, §13.1) |

Le lot 1 (§4) sépare les deux. **Cette séparation est la première chose à valider empiriquement sur device**, avant tout développement carburant.

---

## 3. État des lieux critique du code actuel

À lire avant de modifier quoi que ce soit. Chaque point est un défaut vérifiable, pas une opinion.

### 3.1 La dynamique de conduite est calculée puis jetée

`VehicleFuelCatalog.estimateConsumption(distanceKm:fuelProfile:dynamics:)` (`VehicleFuelCatalog.swift:237-258`) accepte un paramètre `dynamics` **qui n'apparaît pas dans le corps de la fonction**. `TripStore.swift:462-466` fait tourner `DrivingDynamicsAnalyzer` sur tous les échantillons du trajet pour le lui transmettre — pour rien.

Le multiplicateur existe pourtant, complet (`DrivingDynamics.swift:186-213`), et sert **uniquement au score éco** (`ScoreEngine.swift:96`).

Conséquence mesurable : deux trajets de 12 km sur la même Corolla — l'un à 65 km/h sans à-coups, l'autre à 18 km/h avec 11 événements brusques et 35 % de ralenti — produisent **exactement 0,816 L** tous les deux. Un test verrouille ce comportement : `VehicleFuelCatalogTests.swift:26-77`.

Conséquence produit : le même écran affiche un score éco qui annonce une surconsommation et un coût qui l'ignore. Deux chiffres contradictoires côte à côte.

### 3.2 Le catalogue est une constante éditoriale

- **`vehicleYear` est collecté et ignoré.** `profile(vehicleType:brand:model:)` (`VehicleFuelCatalog.swift:185`) ne prend pas l'année. « Toyota Corolla » = 6,8 L/100, que ce soit une 1.4 D-4D de 2005 ou une hybride de 2021 (~40 % d'écart réel).
- **Pas de motorisation, pas de carburant.** Un seul `pricePerLiter` pour toute l'app : diesel et essence indistinguables.
- **Valeurs = cycles mixtes constructeur européens**, appliquées telles quelles au Burkina (latérite, surcharge, clim permanente, entretien espacé). Biais systématique et unidirectionnel de 15 à 30 %.
- **`confidence: .partial` en dur** (`:204`) : « Toyota Corolla » et « Sanili SL 125 → 2,2 L/100 » sortent avec la même confiance affichée.
- **`sourceIdentifier = "ViimCatalog.indicative.v7"`** — c'est-à-dire « nous ». Aucune entrée n'est sourçable.

### 3.3 Bug de résolution du catalogue, reproductible

`resolvedEntry` prend le **premier match dans l'ordre de déclaration** (`entries.first(where:)`, `:268`) et `matches()` teste des **sous-chaînes** (`:493-501`). L'entrée Mazda 3 a pour clé modèle `"3"` — un caractère (`:103`).

Reproduction : `profile(vehicleType: .voiture, brand: "Mazda", model: "CX-30")`
→ `"cx30".contains("3")` = vrai, marque `"mazda"` = vrai, Mazda 3 déclarée avant CX-5
→ **6,7 L/100 attribué en silence à un CX-30**, avec `confidence: .partial`.

Le comportement correct pour un modèle absent est `nil` (c'est ce que teste `testUnknownFuelProfileDoesNotInventCost`). Le catalogue contourne son propre garde-fou. Même mécanique, plus bénigne, pour « Corolla Cross » → Corolla.

### 3.4 Le prix est une saisie présentée comme une preuve

Le libellé affiché est `driving.fuel.evidence` (`ConduiteView.swift:664`), `FuelPriceSource.userProvided` est figé sur le trajet. Ce qui est réellement prouvé : l'utilisateur a tapé un nombre, une fois. Rien ne le périme — un prix de janvier s'applique à un trajet de décembre et s'étiquette « preuve ». `fuelPriceCapturedAt` est affiché (`AccueilView.swift:1191`) mais aucune alerte de fraîcheur n'existe.

### 3.5 Agrégats : tout-ou-rien et circularité

- `TripStore.swift:714-717` : si **un seul** trajet de la période a `fuelLiters == nil`, `totalFuelLiters` devient `nil` et les trois tuiles de l'onglet Conduite affichent « — ». L'utilisateur perd son mois sans savoir pourquoi.
- `ConduiteView.swift:629` affiche `litres / totalKm × 100` comme « consommation moyenne ». Comme `litres = km × catalogue / 100`, cette moyenne **restitue mécaniquement la constante du catalogue**. Pour un utilisateur mono-véhicule, la tuile affichera éternellement « 6,8 L/100 » quoi qu'il conduise. C'est le chiffre le plus trompeur de l'écran, parce qu'il ressemble à une observation. Même circularité pour `costBreakdownText` (coût/km, coût/trajet).

### 3.6 Données de conduite non capturées

| Donnée | Statut | Impact sur la consommation |
|---|---|---|
| Altitude / pente | `CLLocation` la fournit, **non stockée** (`TripStore.swift:54-60`) | 2ᵉ facteur après la vitesse ; une côte à 5 % double la puissance à la roue |
| Accélération inertielle | dérivée du GPS tous les 10 m | résolution grossière, bruitée ; `SensorFiltering.swift` existe déjà |
| Température / pression / vent | absent | à Ouaga (450 m, 35 °C) ρ ≈ 1,06 vs 1,225 standard → −13 % de traînée ; moteur froid → +15 % sur 5 km |
| Revêtement | absent | Crr bitume ≈ 0,012, latérite ≈ 0,025-0,035 — **doublement de la résistance au roulement**, probablement le plus gros facteur ignoré au Burkina |

L'altitude est urgente : gratuite à la capture, **impossible à reconstituer rétroactivement**.

### 3.7 Détection transport collectif : rejet binaire et silencieux

`PublicTransitTripDetector` (`TripReliability.swift:180-245`) exige 5 arrêts distincts de 45-180 s espacés de 500 m, sur ≥ 4 km et ≥ 15 min. En cas de détection, `TripManager.swift:162` appelle `rejectingAsLikelyPublicTransit()` et **le trajet disparaît**.

Trois défauts :

- **Faux positif grave pour le marché cible.** Un taxi, un taxi collectif ou un livreur à Ouaga produit exactement cette signature. Ses trajets disparaissent de son historique — pour un conducteur professionnel, l'app devient inutilisable.
- **Faux négatifs.** Un bus sur trajet court ou express (< 5 arrêts) passe pour une voiture conduite.
- **Disparition silencieuse.** Le trajet n'apparaît nulle part, aucune explication. L'utilisateur conclut que l'app perd des trajets — exactement le grief qui a motivé les blueprints de juillet.

Le détecteur n'exploite ni CoreMotion, ni la récurrence spatiale des arrêts, ni la signature d'accélération — les trois signaux réellement discriminants.

---

## 4. Lot 1 — Indicateur GPS : deux états de session (P0)

### 4.1 Contrainte de plateforme à énoncer clairement

**Il est impossible sur iOS de capturer une localisation continue en arrière-plan sans afficher l'indicateur.** C'est une garantie de confidentialité de la plateforme, et toute tentative de contournement est un motif de rejet App Review. Ne cherche pas de contournement, n'en propose pas.

Ce qui **est** corrigeable, et qui est le problème réel rapporté : l'indicateur reste allumé **alors que l'utilisateur ne conduit pas**, en permanence, jusqu'à ce que l'app soit tuée. Ça, c'est un défaut, et c'est ce que ce lot corrige.

Pendant un trajet actif, l'indicateur reste affiché et c'est légitime : l'utilisateur conduit, l'app enregistre, le signal est honnête.

### 4.2 Machine à deux états

| État | Déclencheur | Localisation | Sessions | Indicateur |
|---|---|---|---|---|
| **Veille** | pas de conduite confirmée | SLC + géofence départ 150 m + `CMMotionActivity` | `CLServiceSession(.always)` seule (iOS 18+) | **éteint** |
| **Trajet** | conduite confirmée | `startUpdatingLocation()` continu | `CLServiceSession` + `CLBackgroundActivitySession` | allumé |

Transition veille → trajet : réveil par géofence (déjà en place, `departureRegionRadiusMeters = 150`, `LocationService.swift:175`), SLC, ou CoreMotion `automotive` en confiance haute.

Transition trajet → veille : à la fin du trajet, **invalider `CLBackgroundActivitySession`** et conserver `CLServiceSession`.

### 4.3 Dégradation par version d'OS

| OS | Comportement |
|---|---|
| **iOS 18+** | cible complète : `CLServiceSession` en veille, indicateur éteint |
| **iOS 17** | pas de `CLServiceSession`. Invalider `CLBackgroundActivitySession` en veille, réveil par géofence 150 m + SLC + CoreMotion. **Risque de latence de départ** — c'est exactement le scénario du 18 juillet. La géofence 150 m et le journal `ActiveTripJournal` sont les mitigations. |
| **iOS 16** | pas de session ; comportement actuel conservé |

**Ne traite pas iOS 17 comme un détail.** Si la validation terrain (§11.4) montre une troncature en iOS 17, la bonne réponse est de conserver l'indicateur permanent sur cette version uniquement et de le documenter — perdre des trajets est pire qu'afficher un indicateur.

### 4.4 Fichiers

`ios/Viim/Services/LocationService.swift` (`:320-380`, `:530-580`), `ios/Viim/Persistence/ActiveTripJournal.swift`.

---

## 5. Lot 2 — Capture enrichie (P0, à faire tôt)

Chaque point de trace doit désormais porter la physique du déplacement.

### 5.1 Altitude

Ajouter à `TripRoutePoint` (`TripStore.swift:54-60`) et `LocationSample` :

```swift
let altitudeMeters: Double
let verticalAccuracy: CLLocationAccuracy
```

Migration Core Data : attributs optionnels, `nil` pour l'historique. La pente se dérive entre points valides, avec un filtre : rejeter les pentes issues de points dont `verticalAccuracy > 10 m` ou dont la pente calculée dépasse 20 % (bruit, pas relief).

**À faire en premier, même sans exploitation immédiate.** C'est gratuit à la capture et irrattrapable après coup.

### 5.2 CoreMotion inertiel

`CMMotionManager.deviceMotion` à 10-25 Hz **pendant les trajets actifs uniquement** (coût batterie). Fournit :

- l'accélération longitudinale réelle, gravité retirée, bien plus fine que la dérivée GPS à 10 m ;
- la signature vibratoire → inférence du revêtement (§8.4) ;
- la discrimination conducteur / passager (§9.2).

Réutiliser `SensorFiltering.swift`. Stocker un résumé agrégé par trajet, **pas** le flux brut (volume).

Point d'attention : l'orientation du téléphone est inconnue et variable. Il faut une estimation du repère véhicule (moyenne glissante de la gravité + axe de déplacement GPS) avant toute projection longitudinale. Si l'orientation n'est pas estimable avec confiance, retomber sur la dérivée GPS et l'indiquer dans la confiance.

### 5.3 Météo (backend)

Route backend renvoyant température, pression et vent pour une position et un horodatage. Sert à :

- ρ_air par la loi des gaz parfaits `ρ = p / (R_spéc · T)` ;
- la pénalité moteur froid sur les premiers kilomètres ;
- la composante vent de la résistance aérodynamique.

Source à choisir et à citer (Open-Meteo, service national). Appel **différé et groupé** après le trajet, jamais bloquant.

---

## 6. Lot 3 — Référentiel de prix officiel (backend)

### 6.1 Route

Suivre le patron déjà en place dans `backend/src/routes/prevention.js:26-40` (`source`, `updatedAt`, `Cache-Control`).

```
GET /v1/fuel-prices?country=BF&fuel=gasoline&date=2026-08-11
```

```json
{
  "source": "SONABHY / Arrêté MCIA n°2026-...",
  "sourceUrl": "https://...",
  "publishedAt": "2026-06-01T00:00:00.000Z",
  "effectiveFrom": "2026-06-03T00:00:00.000Z",
  "effectiveUntil": null,
  "country": "BF", "fuel": "gasoline",
  "currency": "XOF", "pricePerLiter": 750,
  "granularity": "national_administered",
  "confidence": "official"
}
```

### 6.2 Sources par marché

| Marché | Source | Fréquence | Nature |
|---|---|---|---|
| Burkina Faso | SONABHY / arrêté ministériel | quelques fois/an | prix **administré** = exact |
| France | `data.economie.gouv.fr` | quotidien | open data, par station |
| UE | Weekly Oil Bulletin (Commission) | hebdo | officiel |
| Canada | Ressources naturelles Canada | hebdo par ville | officiel |
| USA | EIA, par région PADD | hebdo | officiel |

Le Burkina est le cas le plus favorable : prix administré, donc **exact**, sans incertitude d'échantillonnage. Aucune saisie utilisateur ne pourra jamais égaler ça.

### 6.3 Historique daté — exigence centrale

Table `(pays, carburant, date_effet, prix, devise, source, url)` versionnée. Le trajet fige le prix **en vigueur à sa date**, pas le dernier connu. Un trajet de mars conserve le prix de mars, définitivement.

Les colonnes Core Data existent déjà (`PersistenceController.swift:58-62`). Étendre `FuelPriceSource` avec `officialReference`. Fallback hors ligne : dernier référentiel en cache, avec sa date, confiance dégradée.

### 6.4 Retraits

- champ de saisie prix : `ProfilView.swift:87-148`
- `SupportedCurrency.defaultFuelPricePerLiter` (`OnboardingStore.swift:97-104`)
- `FuelSettings.canSnapshotCost` et la distinction `userProvided` / `unverifiedDefault` : remplacées par la fraîcheur du référentiel

La devise reste un choix utilisateur (affichage) ; le prix ne l'est plus.

---

## 7. Lot 4 — Fiche technique véhicule

### 7.1 Du nombre unique à la fiche

Le catalogue porte aujourd'hui un `litersPer100Km`. Il doit porter :

| Champ | Usage | Source |
|---|---|---|
| masse à vide (kg) | roulement, pente, inertie | EPA / ADEME / EEA |
| Cd × surface frontale (m²) | traînée | constructeur / EEA |
| cylindrée (L) | consommation au ralenti | EPA `vehicles.csv` |
| carburant (essence / diesel) | PCI, prix applicable | idem |
| type de boîte | rendement transmission | idem |
| conso homologuée **+ norme** (NEDC / WLTP) | **ancrage du modèle** (§8.3) | ADEME, VCA UK, EPA |
| plages d'années par génération | résolution par année | idem |

**Sources ouvertes exploitables** : EPA Fuel Economy dataset (US, très complet), ADEME Carlabelling (FR), UK VCA Car Fuel Data, EEA CO₂ Monitoring (UE — masse et conso par version).

**Limite à assumer explicitement** : ces bases couvrent bien Toyota / Peugeot / Renault / Hyundai — l'essentiel du parc voiture importé au Burkina. Elles ne couvrent **pas** Haojue, Sanili, Apsonic, Dayun, Sonlink, Jincheng. Pour les motos, référentiel maison à partir des fiches constructeur, **avec une confiance plus basse assumée et affichée**. C'est une limite de disponibilité de données, pas de méthode — ne la masque pas.

### 7.2 Pipeline

Étendre `tools/generate-vehicle-fuel-catalog.mjs` et `tools/verify-vehicle-fuel-catalog.mjs`, régénérer `shared-data/vehicle-fuel-catalog.json`. L'ADR `decisions/2026-07-29-catalogue-carburant-partage-android.md` impose que toute modification iOS régénère le JSON dans le même changement — **respecte-le**.

### 7.3 Résolution par année et correction du matching

- `vehicleYear` entre dans la clé de résolution → génération.
- Remplacer `first(where:)` par un **scoring meilleur-candidat**.
- **Interdire les clés modèle de moins de 3 caractères** (le `"3"` de Mazda, §3.4) — à faire respecter par le vérificateur, pas seulement par convention.
- Exiger un match sur token plein, pas une sous-chaîne arbitraire.
- Un modèle absent doit rendre `nil`, pas le voisin le plus proche.

### 7.4 Ambiguïté de version, sans rien demander

Si « Toyota Hilux 2015 » recouvre un 2.4 D-4D et un 2.7 essence :

1. **Prior** — part des motorisations dans le parc importé pour ce modèle/année.
2. **Vraisemblance observée** — la conduite discrimine partiellement : accélération maximale soutenue, vitesse maximale atteinte, puissance spécifique observée. Faible sur un trajet, exploitable sur trente.
3. **Postérieur bayésien** affiné trajet après trajet.
4. Si l'ambiguïté persiste : **abaisser la confiance affichée**, ne pas trancher arbitrairement.

Le point 2 est le plus incertain de ce lot — voir §13.4. S'il ne tient pas à l'analyse, livre 1 + 4 et laisse tomber 2 et 3 : le prior seul avec confiance dégradée reste très supérieur à l'existant.

---

## 8. Lot 5 — Modèle de consommation

### 8.1 Bilan de puissance à la roue

```
P_roue(t) = [ m·a·(1+ε)                     ← inertie
            + m·g·sin θ                     ← pente
            + m·g·Crr·cos θ                 ← roulement
            + ½·ρ·Cd·A·(v + v_vent)²  ] · v ← aérodynamique
```

Débit instantané :

- `P_roue > 0` → `Q = (P_roue / η + P_aux) / PCI_volumique`
- `P_roue ≤ 0` → `Q = Q_ralenti` (frein moteur ; hypothèse prudente, la coupure d'injection réduirait davantage)
- véhicule à l'arrêt → `Q = Q_ralenti`, fonction de la cylindrée

Intégration sur tous les échantillons valides du trajet.

Ce modèle réagit **par construction** à la vitesse, à l'accélération, à la pente, au ralenti et au revêtement — l'exigence produit de départ.

### 8.2 Paramètres

| Paramètre | Valeur | Source |
|---|---|---|
| m | masse à vide + 75 kg | fiche technique |
| ε (inertie rotative) | 0,05 voiture / 0,03 moto | littérature |
| Crr | 0,012 bitume / 0,025-0,035 latérite | littérature, à affiner flotte |
| ρ | `p / (R_spéc · T)` | météo backend |
| Cd·A | fiche technique | catalogue |
| PCI volumique | ~32 MJ/L essence, ~35,8 MJ/L diesel | référence |
| Q_ralenti | fonction cylindrée | à calibrer flotte (§11.5) |
| η | **résolu par ancrage** | §8.3 |

### 8.3 Ancrage sur le cycle d'homologation — la clé du « sans saisie »

C'est ce qui rend le modèle défendable sans jamais rien demander à l'utilisateur.

1. Le cycle WLTP (classe 3b : 1 800 s, 23,27 km, pente nulle, conditions standard) est un **profil vitesse-temps public et normalisé**. Idem NEDC pour les véhicules plus anciens.
2. Faire tourner le modèle sur ce cycle avec les paramètres physiques du véhicule.
3. Résoudre **un seul scalaire** — le rendement global η — tel que le modèle reproduise exactement la **consommation homologuée officielle** du véhicule.
4. Appliquer ce η ancré au trajet réel.

Le modèle est calé sur une valeur certifiée par homologation et ne s'en écarte sur route qu'à cause de la physique observée. Chaîne de justification complète et affichable :

> « Votre véhicule est homologué à X L/100 sur le cycle Y. Votre conduite mesurée — vitesse moyenne, ralenti, dénivelé, revêtement — donne Z L/100. »

**Correction homologation → réel.** L'écart entre valeurs d'homologation et consommation réelle est mesuré et publié (ICCT, Spritmonitor) : de l'ordre de +14 % pour WLTP, +35-40 % pour NEDC. Ce facteur s'applique **par norme, avec sa source**, et corrige le biais structurel du §3.2. Vérifie les chiffres courants avant de les coder en dur, et rends-les paramétrables côté backend.

### 8.4 Revêtement

Inférence du type de revêtement à partir de la signature vibratoire CoreMotion (énergie haute fréquence sur l'axe vertical) et de la géométrie de la trace. Deux classes suffisent pour la v1 : **revêtu** / **non revêtu**, avec un état **indéterminé** qui retombe sur `Crr = 0,015` et dégrade la confiance.

Au Burkina c'est potentiellement le plus gros facteur du modèle. Ne le sur-raffine pas pour autant : deux classes bien séparées valent mieux que cinq classes bruitées.

### 8.5 Garde-fous obligatoires

- Résultat borné : jamais négatif, jamais supérieur à 3 × la consommation homologuée par kilomètre.
- Si le trajet est en couverture GPS partielle : **pas de coût**, `reasonCode` explicite. Ne jamais extrapoler sur un trou de couverture.
- Si la fiche technique est incomplète : retomber sur `conso_homologuée × distance` (le modèle actuel) **en le disant** dans la confiance et la source, plutôt que d'inventer une masse ou un Cd.
- `formulaVersion` incrémentée et stockée par trajet — l'infrastructure existe déjà.

### 8.6 Livraison en double calcul

Livrer derrière un flag, avec calcul **des deux modèles en parallèle** et journalisation de l'écart, sur au moins deux semaines de trajets réels avant bascule. Un modèle physique qui diverge de 300 % du catalogue sur un trajet ordinaire signale un bug, pas une découverte.

---

## 9. Lot 6 — Classification du transport collectif

### 9.1 Changement de principe : classer, ne pas supprimer

Remplacer le rejet binaire (§3.7) par une classification à trois états portée par le trajet :

| Classe | Carburant | Score conducteur | Historique |
|---|---|---|---|
| `driverVehicle` | oui | oui | onglet conduite |
| `passengerTransit` | **non** | **non** | visible, section distincte |
| `uncertain` | non | non | visible, marqué |

Un trajet ne disparaît plus jamais. C'est aussi une fonctionnalité en puissance (« vous avez parcouru X km en transport ce mois-ci ») et surtout la fin du grief « l'app perd mes trajets ».

### 9.2 Signaux discriminants, par pouvoir décroissant

1. **Récurrence spatiale des arrêts** — un bus s'arrête toujours aux mêmes points GPS. Sur plusieurs trajets, les arrêts se superposent à quelques mètres. Un embouteillage, non. Signal le plus fort, entièrement gratuit, calculable en local sur l'historique.
2. **Signature d'accélération** — un bus accélère à ~1,0-1,2 m/s² maximum, une voiture à 2,5-3,5. Très discriminant avec CoreMotion à 25 Hz (lot 2).
3. **Manipulation du téléphone en déplacement** — un conducteur ne manipule pas son écran à 40 km/h de façon soutenue. Écran actif + déplacement soutenu → passager. Fort et gratuit.
4. **Régularité de l'espacement** des arrêts (300-800 m en urbain).
5. **Corridors de lignes** — les tracés SOTRACO à Ouaga sont fixes. Un référentiel backend de corridors, sur le même patron que `danger-zones`, permet un match de tracé. À garder pour une v2.

### 9.3 Le faux positif taxi — traiter en priorité

Un taxi collectif à Ouaga produit la signature actuelle (arrêts multiples, prolongés, espacés). Les signaux 2 et 3 le séparent nettement d'un bus : accélération de voiture, téléphone non manipulé. **Sans ces deux signaux, ne durcis pas la détection** — la version actuelle fait déjà disparaître les trajets des conducteurs professionnels, qui sont une part significative du marché cible.

### 9.4 Lien avec le carburant

Un trajet `passengerTransit` ne génère **ni consommation, ni coût, ni score**. C'est l'exigence qui relie ce lot au reste : compter le carburant d'un trajet en bus fausserait directement le budget affiché.

### 9.5 Fichiers

`ios/Viim/Services/TripReliability.swift:169-245`, `ios/Viim/Services/TripQualityEngine.swift:19-45`, `ios/Viim/Services/TripManager.swift:152-165`, `ios/Viim/Services/MotionActivityService.swift`.

---

## 10. Lot 7 — Confiance graduée et affichage

### 10.1 Confiance composite

`MetricConfidence` est aujourd'hui une constante en dur (`VehicleFuelCatalog.swift:204`). Elle devient le produit de quatre facteurs :

```
confiance = qualité_fiche_technique × certitude_version × couverture_GPS × fraîcheur_prix
```

- Corolla 2018 identifiée sans ambiguïté + couverture complète + prix administré du mois → **haute**
- Sanili SL 125 sans fiche + couverture partielle → **faible**, et l'utilisateur le voit

Une confiance qui ne varie jamais n'informe personne.

### 10.2 Corrections d'affichage

- **Tuile « consommation moyenne »** (`ConduiteView.swift:621-631`) : cesse d'être circulaire, affiche la consommation réellement modélisée. Elle devient enfin une information. **Si le lot 5 glisse, retire cette tuile plutôt que de la laisser mentir.**
- **Score éco et coût** dérivent désormais du même modèle physique : fin de la contradiction du §3.1.
- **Agrégat tout-ou-rien** (`TripStore.swift:714-717`) : afficher le total sur les trajets couverts + « N trajets sans estimation », au lieu de « — ».
- **Vocabulaire** : le prix devient une preuve (source officielle datée), la consommation reste une **estimation modélisée**. Distinguer les deux dans l'UI est ce qui tient devant un assureur. Retirer `driving.fuel.evidence` de la consommation.
- **Explicabilité** : un détail de trajet doit pouvoir montrer la décomposition — homologué, effet vitesse, effet pente, effet ralenti, effet revêtement. C'est l'argument assurantiel du produit.

---

## 11. Tests

### 11.1 Modèle de consommation — tests unitaires déterministes

| Test | Attendu |
|---|---|
| **Ancrage** — modèle appliqué au profil WLTP du véhicule | reproduit la conso homologuée à ±0,5 % |
| **Monotonie pente** — même trajet, pente +3 % | consommation strictement supérieure |
| **Monotonie ralenti** — +20 % de temps à l'arrêt | L/100 strictement supérieur, litres/km cohérent |
| **Monotonie agressivité** — mêmes v et distance, accélérations doublées | consommation strictement supérieure |
| **Sensibilité vitesse** — cycle urbain vs cycle routier, même distance | urbain > routier, écart dans une plage plausible |
| **Bornes** | jamais négatif ; jamais > 3 × homologué/km |
| **Dégradation** — fiche technique incomplète | retombe sur homologué × distance, confiance dégradée, source explicite |
| **Couverture partielle** | pas de coût, `reasonCode` explicite |
| **Non-régression §3.1** | les deux trajets de 12 km (fluide vs stop-and-go) donnent désormais des valeurs **différentes** — remplacer `testGpsDynamicsDoNotChangeFinancialConsommationEstimate`, qui verrouille le comportement que ce blueprint supprime |

### 11.2 Catalogue

- `profile(.voiture, "Mazda", "CX-30")` → **`nil`**, pas Mazda 3 (§3.3)
- `profile(.voiture, "Toyota", "Corolla", 2005)` ≠ `profile(.voiture, "Toyota", "Corolla", 2020)`
- Le vérificateur `tools/verify-vehicle-fuel-catalog.mjs` **échoue** si une clé modèle fait moins de 3 caractères
- Le JSON `shared-data/` est identique à la projection du Swift (test existant à étendre)
- Modèle absent du catalogue → `nil` et aucune estimation

### 11.3 Prix (backend, `node:test` comme `backend/test/circle.test.js`)

- Prix daté : un trajet du 15 mars reçoit le prix en vigueur au 15 mars, même si le référentiel a changé depuis
- Réponse hors ligne : cache servi, confiance dégradée, date exposée
- Pays / carburant inconnu → pas de prix, pas de valeur par défaut inventée
- Le snapshot figé sur un trajet n'est **jamais** réécrit par une mise à jour ultérieure du référentiel (test existant à adapter, `TripStoreTests.swift:277-282`)

### 11.4 Indicateur GPS — validation terrain obligatoire

Tests unitaires avec le mock `LocationManaging` (l'interface existe, `LocationService.swift:7-22`) :

- veille → `CLBackgroundActivitySession` absente, `CLServiceSession` présente (iOS 18+)
- trajet actif → les deux présentes
- fin de trajet → `CLBackgroundActivitySession` invalidée, géofence et SLC réarmées
- perte d'autorisation → toutes sessions invalidées

**Validation terrain, non négociable — c'est le scénario du 18 juillet :**

| # | Scénario | Critère |
|---|---|---|
| T1 | App en veille 2 h, téléphone au repos | Indicateur **éteint** tout du long |
| T2 | Démarrage moteur après veille longue, trajet 15 min | Trajet capturé **depuis le départ**, ≤ 200 m manquants au début |
| T3 | Trajet écran verrouillé, 30 min | Aucune troncature, cadence continue |
| T4 | Trajet après terminaison forcée de l'app | Trajet capturé (géofence + SLC) |
| T5 | Fin de trajet, téléphone au repos 30 min | Indicateur éteint dans les 60 s suivant la fin |
| T6 | T1-T5 rejoués sur **iOS 17** | Si T2 ou T4 échoue → conserver l'indicateur permanent sur iOS 17 et documenter |

Documenter dans `qa/artifacts/` selon le format existant.

### 11.5 Transport collectif

- Un trajet taxi simulé (arrêts multiples, accélérations de voiture, téléphone non manipulé) → `driverVehicle`, **pas** de rejet
- Un trajet bus simulé (arrêts récurrents, accélérations ≤ 1,2 m/s², téléphone manipulé) → `passengerTransit`
- Un embouteillage (arrêts non récurrents, non espacés régulièrement) → `driverVehicle`
- Un `passengerTransit` ne génère ni carburant, ni coût, ni score
- **Aucun trajet n'est supprimé** dans les trois cas
- Adapter `TripManagerTests.swift:94-136`, qui teste aujourd'hui la suppression

### 11.6 Validation flotte interne — pas côté utilisateur

La calibration se fait **par l'équipe Viim**, pas par les utilisateurs. Trois véhicules suffisent : une Corolla, un Hilux, une Boxer. Relevés de pleins internes sur ~500 km chacun, comparaison au modèle, publication de l'écart type dans `data-reliability.md`, ajustement de Crr et Q_ralenti.

L'utilisateur final ne saisit jamais rien. C'est ce qui permet de valider un modèle sans transférer le travail sur lui.

---

## 12. Ordre d'exécution

| # | Lot | Justification de l'ordre | Definition of Done |
|---|---|---|---|
| **1** | §5.1 Altitude dans `TripRoutePoint` | Irrattrapable rétroactivement, indépendant du reste | Altitude stockée, migration sans perte, tests verts |
| **2** | §4 Indicateur GPS | Défaut visible en production, indépendant du carburant | T1-T6 passent ; artefact QA publié |
| **3** | §6 Prix officiel + retrait de la saisie | Indépendant, gain immédiat, retire une saisie | Prix daté servi, saisie retirée, tests backend verts |
| **4** | §7 Fiche technique + correction matching | Prérequis du modèle | CX-30 → `nil` ; année discriminante ; JSON régénéré |
| **5** | §5.2 CoreMotion | Prérequis du revêtement et du lot 6 | Accélération inertielle exploitable, orientation gérée |
| **6** | §8 Modèle physique + ancrage, **en double calcul** | Le cœur ; nécessite 1, 4, 5 | Tests §11.1 verts ; 2 semaines de double calcul journalisé |
| **7** | §9 Classification transport | Nécessite 5 | Tests §11.5 verts ; plus aucune suppression |
| **8** | §5.3 Météo + §8.4 revêtement | Raffinements ; le revêtement est le plus rentable | ρ_air appliqué ; deux classes de revêtement |
| **9** | §10 Confiance graduée + UI | Une fois que la confiance a de vraies composantes | Tuile circulaire supprimée ; décomposition affichable |
| **10** | §11.6 Validation flotte | Ferme la boucle | Écart type publié dans `data-reliability.md` |

Les lots 1, 2 et 3 sont indépendants et parallélisables. Le lot 6 est le seul morceau algorithmiquement sérieux.

**Ne bascule pas le modèle physique en production avant le lot 10.** Le double calcul du lot 6 sert précisément à ça.

---

## 13. Points à critiquer avant d'exécuter

Traite ces points en premier. Ils sont classés par gravité si je me trompe.

**13.1 — `CLServiceSession` n'affiche-t-elle vraiment pas l'indicateur ?**
Toute l'architecture du lot 1 en dépend. Le code l'affirme déjà (`LocationService.swift:208-212`) mais aucune trace de vérification empirique n'existe. **Vérifie sur device réel, iOS 18, avant de coder le reste du lot.** Si l'affirmation est fausse, le lot 1 se réduit à iOS 17 (invalidation + géofence, avec le risque de troncature) et il faut me le remonter.

**13.2 — L'ancrage WLTP tient-il pour le parc réel du Burkina ?**
Une Corolla d'occasion importée de 2008 a-t-elle une conso homologuée retrouvable dans les bases ouvertes, sous quelle norme, et avec quelle couverture ? Si le taux de couverture est faible sur le parc réel, l'ancrage ne sert qu'à une minorité et il faut une stratégie de repli explicite (par segment de véhicule ?). **Mesure le taux de couverture sur un échantillon du parc avant de bâtir dessus.**

**13.3 — Le budget batterie de CoreMotion à 25 Hz sur trajet long.**
Chiffre-le. Si c'est prohibitif, propose une cadence adaptative (25 Hz en phase transitoire, 5 Hz en régime stable) ou renonce à l'inertiel et garde la dérivée GPS — auquel cas les lots 8 et 9 perdent leurs signaux 2 et 4, et le blueprint doit être ajusté en conséquence.

**13.4 — La discrimination de motorisation par la conduite (§7.4 point 2).**
C'est le point le plus spéculatif du document. Un 2.4 diesel et un 2.7 essence sont-ils réellement séparables par l'accélération observée sur trente trajets, compte tenu du bruit GPS et de la variabilité du conducteur ? Si tu n'es pas convaincu à l'analyse, **livre le prior seul avec confiance dégradée** — c'est déjà très supérieur à l'existant. Ne code pas un bayésien qui n'apporte rien.

**13.5 — Q_ralenti et Crr avant la calibration flotte.**
Le modèle a besoin de ces deux valeurs dès le lot 6, mais elles ne sont calibrées qu'au lot 10. Propose des valeurs de littérature sourcées et une borne d'incertitude, ou inverse l'ordre si tu juges la calibration bloquante.

**13.6 — Coût réel du lot 4 (fiche technique).**
Combien de véhicules du catalogue actuel trouveront masse, Cd·A et conso homologuée dans les bases ouvertes ? Si c'est moins de la moitié, le modèle physique ne s'applique qu'à une minorité et l'ordre d'exécution doit changer. **Chiffre-le avant de commencer le lot 4**, c'est une demi-journée qui peut réorienter tout le reste.

**13.7 — Signalement libre.**
Si un point de ce blueprint te paraît faux, sur-dimensionné, ou moins prioritaire qu'autre chose que tu vois dans le code, dis-le. Ce document est une proposition argumentée, pas une commande.

---

## 14. Limite assumée

Sans mesure physique du carburant chez l'utilisateur, le nombre de litres reste **modélisé, jamais mesuré**. Ce que ce blueprint change, c'est que chaque terme du modèle devient sourçable — fiche technique publique, homologation certifiée, prix officiel daté, physique standard, mesures GPS et inertielles du trajet — au lieu de reposer sur une constante inventée et une saisie invérifiable.

Le coût devient **explicable ligne par ligne**, ce qui est le vrai critère pour un usage assurantiel. Le prix, lui, devient exact.

L'affichage doit refléter cette distinction sans ambiguïté : **prix = preuve, consommation = estimation modélisée**.

---

## 15. Hors périmètre

- Véhicules hybrides et électriques
- Plusieurs véhicules actifs par compte
- Lecture OBD-II
- Corridors de lignes de transport (§9.2 signal 5) — v2
- Toute saisie utilisateur relative au carburant, sous quelque forme que ce soit
