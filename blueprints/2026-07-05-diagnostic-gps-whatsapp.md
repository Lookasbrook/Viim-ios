# Diagnostic GPS et test WhatsApp - 2026-07-05

## Résumé court

Deux problèmes distincts peuvent expliquer le comportement vu sur l'iPhone.

1. Le GPS n'est pas fiable en arrière-plan dans le code actuel. `LocationService` ne demande que l'autorisation `When In Use`, mais les réveils passifs et `allowsBackgroundLocationUpdates` ne s'activent que si iOS retourne `authorizedAlways`.
2. Le test WhatsApp peut échouer même si le serveur est en ligne. L'onboarding permet d'enregistrer un contact d'urgence au format libre, alors que le backend refuse tout numéro qui n'est pas exactement `+226` suivi de 8 chiffres, sans espaces.

Vérification production faite le 2026-07-05 02:50 UTC :

- `GET https://api.burktech-ia.com/health` -> HTTP 200, `{"status":"ok","api":"ok","db":"ok","whatsapp":"ok","version":"0.1.0"}`
- `POST https://api.burktech-ia.com/v1/alerts/test` avec `{}` -> HTTP 422, `{"error":"invalid_contact"}`
- `POST https://api.burktech-ia.com/v1/alerts/location-share` avec `{}` -> HTTP 422, `{"error":"invalid_contact"}`

Conclusion : les routes WhatsApp sont bien déployées aujourd'hui. Si le bouton test échoue avec un vrai contact, il faut chercher côté format du contact, contrat d'envoi NEwAGENT, ou gestion d'erreur iOS.

## Preuves dans le code

### GPS

- `ios/Viim/Services/LocationService.swift:135-141` appelle uniquement `requestWhenInUseAuthorization()`.
- `ios/Viim/Services/LocationService.swift:210-216` met `allowsBackgroundLocationUpdates = authorizationState == .authorizedAlways`.
- `ios/Viim/Services/LocationService.swift:219-231` lance `startMonitoringSignificantLocationChanges()` uniquement avec `authorizedAlways`.
- `ios/Viim/App/ViimApp.swift:45-52` démarre `prepareForForegroundUse()` et `CoreMotion` après onboarding, mais `CoreMotion` seul ne réveille pas une app suspendue comme le fait la localisation significative.
- `ios/Viim/Features/Assistance/AssistanceView.swift:336-339` appelle `prepareForForegroundUse()` sur l'écran localisation, mais ne force pas une localisation ponctuelle. Si `latestLocation` est vide, l'utilisateur reste sur "Position en attente".
- `ios/Viim/Services/LocationService.swift:288-340` ne démarre un trajet qu'après vitesse >= 10 km/h soutenue 30 s, puis ne le termine/persiste qu'après les règles de fin. Un court déplacement ou un test immobile ne créera pas de trajet.
- `ios/Viim/Persistence/TripStore.swift:104` écrit les trajets avec `synced = false`. Aucun `SyncManager` n'existe encore. Si "mes données GPS" veut dire "dans le backend", elles ne sont pas encore synchronisées.

### WhatsApp

- `ios/Viim/Onboarding/OnboardingView.swift:320-323` valide seulement que le nom et le téléphone du contact d'urgence sont tous les deux présents ou tous les deux absents.
- `ios/Viim/Onboarding/OnboardingView.swift:257-264` sauvegarde le téléphone du contact tel quel. Exemple problématique : `+226 70 00 00 00`.
- `ios/Viim/Features/Assistance/AssistanceView.swift:420-423` impose bien `^\+226\d{8}$` dans l'écran de modification des contacts, mais pas dans l'onboarding initial.
- `backend/src/routes/alerts.js:4` et `backend/src/routes/alerts.js:123-134` refusent les numéros qui ne matchent pas `^\+226\d{8}$`.
- `ios/Viim/Services/BackendAPIClient.swift:51-57` jette seulement `serverStatus(statusCode)` sans conserver le body JSON.
- `ios/Viim/Features/Assistance/AssistanceView.swift:149-156` affiche toujours la même erreur pour 422, 503, DNS, TLS ou absence réseau.
- `backend/src/services/newagent.js:3-17` vérifie NEwAGENT avec un GET pour `/health`, mais l'envoi réel utilise un POST différent à `backend/src/services/newagent.js:19-45`. Le health `whatsapp:"ok"` ne prouve pas que le contrat POST d'envoi est correct.

## Causes probables classées

### GPS-101 - Autorisation background manquante

Statut : bloquant pour les trajets écran verrouillé.

Le code a volontairement supprimé l'escalade automatique vers `Always` pour éviter l'indicateur GPS permanent. C'était bon pour la discrétion, mais la conséquence est claire : une installation fraîche ne peut pas garantir la collecte en arrière-plan.

Fix builder :

1. Ajouter un flux explicite "Activer la détection en arrière-plan" après l'autorisation `When In Use`.
2. Appeler `requestAlwaysAuthorization()` seulement après une explication claire et un geste utilisateur.
3. Dans l'Accueil, afficher deux états différents :
   - `Position active dans l'app` : trajets possibles seulement app ouverte.
   - `Détection arrière-plan active` : trajets possibles écran verrouillé.
4. Si l'utilisateur refuse `Always`, ne pas promettre de collecte écran verrouillé.

### GPS-102 - Pas de localisation ponctuelle pour l'écran Assistance

Statut : majeur pour "Voir ma localisation" et partage de position.

`AssistanceLocationView` prépare les permissions mais ne demande pas `requestLocation()` et ne lance pas un suivi court. Donc `latestLocation` peut rester `nil` même avec l'autorisation.

Fix builder :

1. Ajouter `LocationService.requestCurrentLocation()` pour appeler `CLLocationManager.requestLocation()`.
2. Mettre à jour `latestLocation` sur retour valide.
3. Sur l'écran Assistance, demander une position fraîche à l'ouverture.
4. Afficher un état "Recherche de position" puis une erreur exploitable si délai > 10 s.

### GPS-103 - Collecte locale seulement, pas de sync backend

Statut : majeur si Guy cherche les données côté serveur.

Les trajets terminés sont écrits en CoreData avec `synced=false`, mais aucun `SyncManager` / endpoint `/trips/batch` n'est implémenté dans le code actuel.

Fix builder :

1. Implémenter `SyncManager` avec `NWPathMonitor`.
2. Ajouter endpoint backend `/v1/trips/batch`.
3. Marquer les trajets `synced=true` seulement après succès serveur.
4. Afficher `pendingSyncCount` dans l'Accueil comme état réseau réel.

### GPS-104 - Perte possible d'un trajet actif lors d'un stop forcé

Statut : mineur à moyen.

`stopMonitoring()` appelle `resetDetectionState()` et met `activeTrip = nil`. Le flux principal évite ça quand un trajet est actif, mais un cas lifecycle/profil/erreur permission pourrait perdre un trajet actif.

Fix builder :

1. Avant reset, si `activeTrip != nil`, finaliser ou sauvegarder un brouillon.
2. Ajouter un test de non-régression sur "stop pendant trajet actif".

### WA-101 - Contact d'urgence invalide depuis onboarding

Statut : cause la plus probable du message "test WhatsApp n'a pas abouti".

Le backend exige `+226XXXXXXXX`. L'onboarding accepte des formats humains avec espaces ou un numéro incomplet. Le bouton test envoie ensuite le contact tel quel et reçoit probablement HTTP 422.

Fix builder :

1. Créer un normaliseur partagé iOS, par exemple `BurkinaPhoneNumber.normalize(_:) -> String?`.
2. Accepter les saisies humaines `70 00 00 00`, `+226 70 00 00 00`, `00226...`, puis stocker exactement `+22670000000`.
3. Utiliser le même normaliseur dans onboarding et écran contacts.
4. Au chargement d'un ancien contact Keychain, si le numéro ne se normalise pas, afficher "Contact à corriger" et désactiver le test.

### WA-102 - Erreurs API trop opaques dans l'app

Statut : majeur pour diagnostic terrain.

L'app transforme tous les échecs en "Vérifiez le réseau et la configuration du serveur". Ce message cache les cas exploitables : contact invalide, backend 503, DNS, TLS, timeout.

Fix builder :

1. Faire décoder les réponses d'erreur JSON dans `BackendAPIClient`.
2. Mapper :
   - 422 `invalid_contact` -> "Numéro invalide. Format attendu : +226XXXXXXXX."
   - 503 `newagent_unavailable` -> "Serveur WhatsApp indisponible. Réessayez ou utilisez SMS."
   - `URLError.notConnectedToInternet` -> "Pas de connexion internet."
   - timeout -> "Serveur trop lent. Réessayez."
3. Logger en diagnostic public : endpoint, status code, error code. Ne jamais logger token, fiche médicale ou contenu complet du message.

### WA-103 - Health WhatsApp insuffisant

Statut : majeur pour production.

`/health` vérifie que NEwAGENT répond en GET. L'envoi WhatsApp réel est un POST avec payload `{source, channel, kind, to, message, metadata}`. NEwAGENT peut accepter le GET et refuser le POST.

Fix builder :

1. Ajouter des logs backend scrubbed dans `dispatchWhatsApp` : `kind`, status HTTP provider, code erreur provider.
2. Garder les tokens et numéros masqués.
3. Ajouter un test d'intégration contrôlé avec un contact consenti.
4. Optionnel : endpoint admin de dry-run si NEwAGENT le supporte, sinon ne pas déclarer `whatsapp:"ok"` comme preuve d'envoi réel.

### WA-104 - Fallback SMS et cascade non implémentés

Statut : majeur pour les vraies alertes.

La spec promet cascade contact 1 -> 2 -> 3 et SMS fallback, mais `backend/src/routes/alerts.js` envoie seulement au premier contact et l'app n'a pas de fallback MessageUI branché sur les erreurs 503/offline.

Fix builder :

1. Persister les alertes côté backend sans fiche médicale durable.
2. Ajouter job de cascade après timeout de lecture ou timeout provider.
3. Ajouter fallback SMS côté iOS pour collision/urgence si backend indisponible.
4. Ne pas utiliser SMS fallback pour le résumé quotidien.

## Ordre de correction recommandé

1. Corriger WA-101 et WA-102 d'abord. C'est le chemin le plus court pour expliquer l'erreur actuelle du bouton test.
2. Ajouter le test réel WhatsApp avec contact consenti et logs backend scrubbed. Si ça échoue encore, inspecter le status NEwAGENT POST.
3. Corriger GPS-102 pour que "Voir ma localisation" marche immédiatement dans l'app.
4. Ajouter le flux explicite `Always` pour GPS-101, puis refaire un roulage écran verrouillé.
5. Implémenter `SyncManager` seulement après validation que les trajets se créent bien localement.
6. Mettre à jour `qa/known-issues.md` et `qa/test-results.md`. La ligne ASSIST-002 en 404 est obsolète depuis la vérification production du 2026-07-05.

## Tests pertinents

### Tests déjà exécutés pendant cette investigation

- `npm ci --prefix backend`
- `npm test --prefix backend`
  - Résultat : 4 tests backend OK. Les tests doivent être lancés hors sandbox car ils ouvrent un serveur local `127.0.0.1`.
- `xcodebuild test -project ios/Viim.xcodeproj -scheme Viim -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/viim-deriveddata`
  - Résultat : 16 tests iOS OK.
- `curl -s -i https://api.burktech-ia.com/health`
  - Résultat : HTTP 200, health OK.
- `curl -s -i -X POST https://api.burktech-ia.com/v1/alerts/test -H 'Content-Type: application/json' -d '{}'`
  - Résultat : HTTP 422 `invalid_contact`, donc route déployée.

### Tests automatisés à ajouter

1. XCTest `BurkinaPhoneNumberTests`
   - `"+226 70 00 00 00"` -> `"+22670000000"`
   - `"70 00 00 00"` -> `"+22670000000"`
   - `"+2250700000000"` -> invalide
   - `"+2267000000"` -> invalide
2. XCTest onboarding
   - Impossible de terminer avec contact d'urgence non normalisable.
   - Contact sauvegardé en Keychain toujours normalisé.
3. XCTest `BackendAPIClientTests` avec `URLProtocol` stub
   - 422 `invalid_contact` mappe vers une erreur utilisateur contact.
   - 503 `newagent_unavailable` mappe vers erreur serveur WhatsApp.
   - URL appelée : `https://api.burktech-ia.com/v1/alerts/test`.
4. XCTest `LocationServiceTests`
   - `requestCurrentLocation()` demande une position ponctuelle.
   - `authorizedWhenInUse` ne doit pas afficher "arrière-plan actif".
   - `authorizedAlways` active `allowsBackgroundLocationUpdates` et les changements significatifs.
5. Tests Node backend
   - Provider qui retourne 500 -> API retourne 503 sans fuite du body sensible.
   - Contact avec espaces -> 422 tant que le backend ne normalise pas.
   - Si normalisation backend ajoutée, contact avec espaces -> 200 avec numéro normalisé.

### Tests manuels iPhone réel

1. GPS foreground
   - Installation fraîche.
   - Autoriser "Lorsque l'app est active".
   - Ouvrir Accueil, rouler 5 minutes avec l'app ouverte, vitesse > 10 km/h.
   - Attendu logs : `motion.triggerLocationMonitoring`, `location.start active`, `trip.begin`, puis `trip.end` / `trip.persisted`.
2. GPS arrière-plan
   - Activer explicitement "Toujours" dans l'app ou Réglages iOS.
   - Verrouiller l'écran, rouler 20 minutes.
   - Attendu logs : `location.authorization state=authorizedAlways`, `location.passiveWakeups.start`, `location.passiveWakeup.promote`, `trip.persisted`.
   - Attendu CoreData : au moins une ligne `ZTRIP`.
3. Assistance localisation
   - Ouvrir Assistance -> Voir ma localisation sans rouler.
   - Attendu : carte et coordonnées fraîches en moins de 10 s, précision <= 100 m.
4. WhatsApp contact invalide
   - Entrer `+226 70 00 00 00`.
   - Attendu : l'app normalise vers `+22670000000` ou affiche une erreur avant sauvegarde.
5. WhatsApp test réel
   - Contact WhatsApp consenti, numéro normalisé.
   - Appuyer "Envoyer un test WhatsApp".
   - Attendu : HTTP 200 côté backend, provider status 2xx, message reçu.
6. WhatsApp panne réseau
   - Mode avion.
   - Attendu : message "Pas de connexion internet", pas "configuration serveur".
7. WhatsApp provider down
   - Simuler provider 503 en staging.
   - Attendu : erreur serveur WhatsApp, et fallback SMS proposé pour urgence/collision quand cette partie sera implémentée.

## Critères d'acceptation

- Un contact d'urgence invalide ne peut plus être stocké depuis l'onboarding.
- Le bouton test WhatsApp affiche une cause claire pour 422, 503, offline et timeout.
- Un test WhatsApp réel avec contact consenti est reçu.
- "Voir ma localisation" obtient une position sans attendre un trajet.
- L'app ne prétend pas collecter en arrière-plan tant que `Always` n'est pas accordé.
- Un roulage iPhone réel écran verrouillé crée un `Trip` local quand `Always` est accordé.
- Les docs QA ne disent plus que `/v1/alerts/*` retourne 404 en production.
