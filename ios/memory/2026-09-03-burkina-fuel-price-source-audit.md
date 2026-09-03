# Audit des sources de prix carburant au Burkina Faso

Date de verification : 2026-09-03.

## Decision Build 50

Viim ne charge automatiquement aucun prix carburant au Burkina Faso. La seule
source autorisee pour figer un cout BF/XOF reste un prix saisi explicitement par
l'utilisateur. Une recherche automatique non couverte echoue avant tout appel
HTTP au backend ou a un fournisseur de prix et ne remplace jamais le prix deja
enregistre.

Cette decision est volontairement fail-closed : une valeur plausible n'est pas
une preuve de prix actuel.

## Sources verifiees

### SONABHY

- Page officielle : <https://www.sonabhy.bf/tarif-hydrocarbures/>.
- Le site consomme un endpoint Strapi public :
  <https://king-prawn-app-6bsvl.ondigitalocean.app/api/tarif-consommateurs?populate=*>
- Au 2026-09-03, ce JSON contient deux objets portant la meme date d'arrete
  `2026-07-08` mais des objets juridiques differents :
  - arrete 2026-007, structure de prix : gazole 675 XOF/L ;
  - arrete 2026-008, prix de vente au detail : gazole 750 XOF/L a Ouagadougou
    et 745 XOF/L a Bobo-Dioulasso.
- L'endpoint est HTTPS mais se trouve sur un domaine DigitalOcean generique,
  n'est ni documente ni versionne, et aucune licence de reutilisation SONABHY
  n'a ete trouvee. La page officielle porte `All Rights Reserved`.
- Integrer directement cet endpoint dans l'iPhone ferait dependre un calcul
  financier d'un schema prive susceptible de changer sans preavis et demanderait
  d'interpreter la nature juridique des arretes. Il est donc rejete.

### INSD

- Catalogue officiel mensuel :
  <https://www.insd.bf/index.php/fr/statistiques/statistiques-economiques/statistiques-des-prix>.
- Fichier structure le plus recent trouve lors de l'audit :
  <https://www.insd.bf/sites/default/files/2026-07/NOTE_IHPC_Base_2023_de_MAI_2026.xlsx>.
- Le classeur publie des moyennes regionales de mai 2026. Il contient notamment
  essence super 850 XOF/L et gazole 675 XOF/L pour le Kadiogo.
- Licence ouverte : <https://www.insd.bf/fr/licence-data-insd>. La reutilisation,
  y compris commerciale, est autorisee avec attribution.
- Ce flux est un catalogue HTML et un fichier XLSX, pas une API documentee. Plus
  important, la moyenne de mai ne reflete pas le tarif de detail SONABHY de
  juillet/aout. Il est donc impropre a l'etiquette « prix actuel ».

## Condition de future activation

Un fournisseur Burkina pourra etre active seulement si les six preuves suivantes
sont simultanement disponibles :

1. source officielle et droit de reutilisation explicite ;
2. endpoint HTTPS stable, documente ou miroir Viim controle ;
3. distinction non ambigue entre structure de prix et tarif de vente au detail ;
4. date d'effet et date de recuperation ;
5. correspondance explicite ville/region, devise XOF et type de carburant ;
6. tests de schema, fraicheur, redirection, taille, doublons et panne reseau.

Une ingestion backend avec validation humaine de l'arrete SONABHY est la voie
recommandee. L'app ne devra jamais interroger directement l'endpoint Strapi.
