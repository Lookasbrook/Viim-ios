# Attributions des photos de véhicules

Photos intégrées localement dans `ios/Viim/Resources/Assets.xcassets`. Elles sont redimensionnées à 1200 px maximum et ne déclenchent aucun appel réseau dans l'app. Une photo n'est affichée que lorsque la marque et le modèle saisis correspondent au catalogue local.

Contrôle du 2026-09-03 : les 22 auteurs, licences, types MIME JPEG et empreintes
SHA-1 de révision ont été relus via l'API officielle Wikimedia Commons. Le manifeste
exécutable se trouve dans `VehiclePhotoCatalog.swift` ; une entrée sans source HTTPS,
auteur, licence autorisée, empreinte ou méthode `photograph` est automatiquement
exclue. L'app affiche près de chaque image les liens vers le fichier source et la
licence, ainsi que la mention de redimensionnement. Aucun traitement génératif n'a
été appliqué.

Les six ajouts du 2026-09-03 sont des photographies inspectées visuellement :
Honda Wave 110 Special Edition 2026, Suzuki GN 125, Toyota Fortuner AN160,
Nissan X-Trail T33, Hyundai Tucson NX4 et Kia Sportage NQ5. Les quatre photos de
voitures récentes ne sont affichées que si l'année du profil appartient à la
génération représentée ; sinon l'app conserve l'illustration neutre. Aucune photo suffisamment
précise et licenciée n'a été trouvée pour TVS HLX 125 ou Bajaj Boxer BM 100 ; ces
modèles conservent donc l'illustration neutre.

| Asset | Source | Auteur | Licence |
| --- | --- | --- | --- |
| `VehiclePhotoToyotaCorolla` | [Toyota Corolla Altis Front 27082022](https://commons.wikimedia.org/wiki/File:Toyota_Corolla_Altis_Front_27082022.jpg) | Poramin | CC BY-SA 4.0 |
| `VehiclePhotoToyotaHilux` | [2020 Toyota Hilux E](https://commons.wikimedia.org/wiki/File:2020_Toyota_Hilux_E_(front_left_side_view).jpg) | Ethan Llamas | CC BY-SA 4.0 |
| `VehiclePhotoToyotaRAV4` | [Toyota RAV4 (5th Gen.) front look](https://commons.wikimedia.org/wiki/File:Toyota_RAV4_(5th_Gen.)_front_look.jpg) | Wh.0414.justin | CC BY-SA 4.0 |
| `VehiclePhotoToyotaYaris` | [2020-2024 Toyota Yaris](https://commons.wikimedia.org/wiki/File:2020-2024_Toyota_Yaris.jpg) | TTTNIS | CC0 1.0 |
| `VehiclePhotoToyotaFortuner` | [2018 Toyota Fortuner TRD Sportivo looking from front](https://commons.wikimedia.org/wiki/File:2018_Toyota_Fortuner_TRD_Sportivo_looking_from_front.jpg) | VulcanSphere | CC BY 4.0 |
| `VehiclePhotoNissanXTrail` | [Nissan X-TRAIL G 2WD (6AA-T33) front](https://commons.wikimedia.org/wiki/File:Nissan_X-TRAIL_G_2WD_(6AA-T33)_front.jpg) | Tokumeigakarinoaoshima | CC0 1.0 |
| `VehiclePhotoHyundaiTucson` | [Hyundai Tucson (NX4) 091227](https://commons.wikimedia.org/wiki/File:Hyundai_Tucson_(NX4)_091227.jpg) | Trop86 | CC0 1.0 |
| `VehiclePhotoKiaSportage` | [2023 Kia Sportage (NQ5) in White, front left](https://commons.wikimedia.org/wiki/File:2023_Kia_Sportage_(NQ5)_in_White,_front_left.jpg) | Benespit | CC BY-SA 4.0 |
| `VehiclePhotoRenaultDuster` | [Moscow, Renault Duster Aug 2025 01](https://commons.wikimedia.org/wiki/File:Moscow,_Renault_Duster_Aug_2025_01.jpg) | Retired electrician | CC0 1.0 |
| `VehiclePhotoKiaPicanto` | [Kia Picanto GT Line (III) — f 01062025](https://commons.wikimedia.org/wiki/File:Kia_Picanto_GT_Line_(III)_–_f_01062025.jpg) | M 93 | CC BY-SA 3.0 DE |
| `VehiclePhotoNissanNavara` | [Nissan Navara 4x2 VE 2025 (3)](https://commons.wikimedia.org/wiki/File:Nissan_Navara_4x2_VE_2025_(3).jpg) | Captainmorlypogi1959 | CC BY-SA 4.0 |
| `VehiclePhotoToyotaPrado` | [2013-2017 Toyota Land Cruiser Prado](https://commons.wikimedia.org/wiki/File:2013-2017_Toyota_Land_Cruiser_Prado_(front).jpg) | Self-Proclaimed-Car-Enthusiast | CC BY-SA 4.0 |
| `VehiclePhotoToyotaLandCruiser` | [2023 Toyota Land Cruiser 70](https://commons.wikimedia.org/wiki/File:2023_Toyota_Land_Cruiser_70_front_left.jpg) | TTTNIS | CC0 |
| `VehiclePhotoYamahaCrypton` | [Crypton](https://commons.wikimedia.org/wiki/File:Crypton.jpg) | Thigre | CC BY-SA 4.0 |
| `VehiclePhotoYamahaYBR` | [Yamaha YBR-125 Kiev1](https://commons.wikimedia.org/wiki/File:Yamaha_YBR-125_Kiev1.JPG) | Kyrylo Danylchenko | Public domain |
| `VehiclePhotoYamahaFZS` | [Fz bike](https://commons.wikimedia.org/wiki/File:Fz_bike.jpg) | Rosinisubramani | CC BY-SA 4.0 |
| `VehiclePhotoBajajBoxer` | [Bajaj Boxer BM 150](https://commons.wikimedia.org/wiki/File:Bajaj_Boxer_BM_150.jpg) | Axxter99 | CC BY-SA 4.0 |
| `VehiclePhotoTVSApache` | [TVS Apache RTR 200 4V](https://commons.wikimedia.org/wiki/File:TVS_Apache_RTR_200_4V_Front-Right_Profile.jpg) | OffPoynt | CC BY-SA 4.0 |
| `VehiclePhotoHondaCG125` | [Honda CG125](https://commons.wikimedia.org/wiki/File:Honda_CG125.jpg) | SEDJRO SETONDJI | CC BY-SA 4.0 |
| `VehiclePhotoHondaCB125F` | [CB 125 F in Pakistan](https://commons.wikimedia.org/wiki/File:CB_125_F_in_Pakistan.jpg) | Hasan HH | CC BY-SA 4.0 |
| `VehiclePhotoHondaWave110` | [2026 Honda Wave 110 Special Edition](https://commons.wikimedia.org/wiki/File:2026_Honda_Wave_110_Special_Edition_(Alloy_Type).jpg) | Chanokchon | CC BY-SA 4.0 |
| `VehiclePhotoSuzukiGN125` | [Suzuki GN 125 DSCF0735](https://commons.wikimedia.org/wiki/File:Suzuki_GN_125_DSCF0735.JPG) | Addvisor | CC BY-SA 4.0 |
