package com.yamstack.viim.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yamstack.viim.core.*

private val Navy = Color(0xFF12345B)
private val Blue = Color(0xFF1E73BE)
private val Green = Color(0xFF207561)
private val Red = Color(0xFFC43B3B)

@Composable
fun ViimTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = lightColorScheme(primary = Navy, secondary = Blue, tertiary = Green), content = content)
}

private enum class ViimTab(val label: String, val icon: @Composable () -> Unit, val tint: Color) {
    ACCUEIL("Accueil", { Icon(Icons.Default.Home, null) }, Navy),
    CONDUITE("Conduite", { Icon(Icons.Default.DirectionsCar, null) }, Blue),
    ASSISTANCE("Assistance", { Icon(Icons.Default.Warning, null) }, Red),
    PREVENTION("Prévention", { Icon(Icons.Default.Shield, null) }, Green)
}

@Composable
fun ViimRoot() {
    var tab by rememberSaveable { mutableStateOf(ViimTab.ACCUEIL) }
    Scaffold(
        bottomBar = {
            NavigationBar {
                ViimTab.entries.forEach { item ->
                    NavigationBarItem(selected = tab == item, onClick = { tab = item }, icon = item.icon, label = { Text(item.label) })
                }
            }
        }
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when (tab) {
                ViimTab.ACCUEIL -> HomeScreen()
                ViimTab.CONDUITE -> DrivingScreen()
                ViimTab.ASSISTANCE -> AssistanceScreen()
                ViimTab.PREVENTION -> PreventionScreen()
            }
        }
    }
}

@Composable private fun Screen(title: String, subtitle: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp), content = {
        Text(title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant)
        content()
    })
}

@Composable private fun HomeScreen() = Screen("Bonjour", "Votre sécurité et vos trajets, au même endroit.") {
    StatusCard("Détection automatique", "Prête — l’autorisation GPS est demandée uniquement au démarrage du suivi.", Green)
    StatusCard("Historique", "La reconstruction ne copie aucune donnée de l’APK installée. Les nouveaux trajets resteront locaux.", Navy)
}

@Composable private fun DrivingScreen() = Screen("Conduite", "Les scores reprennent la formule iOS : vitesse, fluidité et éco-conduite.") {
    StatusCard("Score de conduite", "En attente d’un trajet GPS de qualité suffisante.", Blue)
    Text("Un trajet doit durer au moins 60 s, contenir deux points GPS valides et dépasser 80 m avant d’être conservé.")
}

@Composable private fun AssistanceScreen() = Screen("Assistance", "Préparer une alerte sans exposer vos contacts ou votre dossier médical.") {
    StatusCard("Cercle de confiance", "À réactiver quand le backend et les règles de confidentialité seront validés.", Red)
    Text("Les coordonnées, données médicales et positions de l’ancienne application n’ont pas été lues depuis le Pixel.")
}

@Composable private fun PreventionScreen() = Screen("Prévention", "Entretien, zones à risque et informations utiles pour votre véhicule.") {
    StatusCard("Carburant", "Contrat partagé v1 intégré : coût estimé et coût confirmé restent distincts.", Green)
    StatusCard("Entretien", "Le module métier sera porté après la validation de la persistance Android (Room).", Navy)
}

@Composable private fun StatusCard(title: String, detail: String, color: Color) {
    Card(colors = CardDefaults.cardColors(containerColor = color.copy(alpha = .10f))) {
        Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            Icon(Icons.Default.CheckCircle, null, tint = color)
            Column { Text(title, fontWeight = FontWeight.SemiBold); Text(detail, style = MaterialTheme.typography.bodyMedium) }
        }
    }
}
