# Audit de fiabilité du 12 septembre 2026

Suite de l'audit : voir [le plan exécuté du build 52](FIX-PLAN-BUILD-52.md)
pour les corrections supplémentaires, les 422 tests et l'installation sur
l'iPhone. Les constats et la portée ci-dessous décrivent la première passe.

## Éléments vérifiés

Lecture du conteneur de Viim sur l'iPhone connecté, sans modification de ses
données. Build observé : 0.1.0 (51). Copie de travail privée dans
`/tmp/viim-audit.Cr3wFr/device` ; aucun journal personnel ajouté au dépôt.

- Neuf trajets depuis le 10 septembre, tous sans estimation de carburant.
  Le catalogue ne reconnaissait pas `Corolla Le`. L'alias est ajouté avec une
  référence **indicative**, et non une consommation mesurée ou une fiche LE
  officielle. Les anciens trajets ne sont pas recalculés avec le véhicule ou
  le prix actuels, faute de preuve historique suffisante.
- Ces neuf trajets ont une couverture calculée de 0,59 à 0,71 et un trou GPS
  maximal de 290 à 361 secondes. Le badge « Données partielles » est justifié.
  Une bonne précision ponctuelle ne prouve pas la continuité du trajet.
- Le moteur de score pouvait rendre 100 sans paire de mesures exploitable,
  ou généraliser quelques secondes à tout un trajet. La nouvelle version
  exige 80 % de couverture temporelle par intervalles exploitables. Les scores
  historiques avec une couverture connue sous ce seuil sont masqués à la
  lecture et exclus des moyennes, sans réécriture du stockage.
- Les logs indiquent `authorizedAlways`, `alwaysServiceSession=true`,
  `backgroundSession=false`. La suppression de la session qui force la
  pastille était déjà présente dans les modifications locales et dans les
  logs du build installé. Ne pas la présenter comme un nouveau correctif.
- Collision : `alerts=false network=false`, état public `unavailable`.
  Le mode de calibration ne constitue pas un système d'alerte opérationnel.
- Contact : `configuredUnverified:count=1`. Cela signifie absence de preuve
  de livraison, pas preuve que le contact est injoignable. Aucun message de
  test n'a été envoyé. L'accès à l'outil interne de revue des collisions est
  désormais réservé aux builds DEBUG ; l'indisponibilité reste visible.

## Point encore ouvert : interruptions GPS

Le journal montre des interruptions répétées des capteurs autour de cinq
minutes, mais ne permet pas d'en attribuer la cause à l'économie de batterie.
La configuration demande déjà les mises à jour en arrière-plan, désactive
les pauses automatiques et dispose du mode `location` dans Info.plist.
Ni un assouplissement du badge ni une interpolation ne réparent la trace.

Les nouveaux événements `app.scene`, `location.deliveryGap`,
`location.systemPaused` et `location.systemResumed` permettront de corréler
l'état de l'app, le mode économie d'énergie et les livraisons Core Location,
sans journaliser les coordonnées. Validation terrain restante : installer
le build corrigé, effectuer un trajet écran verrouillé puis lire ces événements
et la télémétrie de couverture. Ne pas déclarer le suivi corrigé avant cela.

## Indicateur iOS

`showsBackgroundLocationIndicator=false` contrôle la pastille bleue sous
autorisation Toujours. La flèche système indiquant l'utilisation de la
localisation est distincte et n'est pas un élément de l'interface de Viim.

- https://developer.apple.com/documentation/corelocation/cllocationmanager/showsbackgroundlocationindicator
- https://support.apple.com/en-ie/102515

## Portée

Validation : suite complète réussie sur simulateur iOS 26.5 (414 tests),
compilation Release pour iPhone réussie sans signature, `git diff --check`
sans erreur. Résultats locaux : `/tmp/viim-audit.Cr3wFr/verified.xcresult`.

Les modifications préexistantes du dossier ont été conservées. Aucun
déploiement backend, envoi d'alerte, remplacement de la base de l'iPhone ou
activation de la détection de collision n'a été effectué. Les changements
de cette session doivent encore être installés sur l'iPhone.
