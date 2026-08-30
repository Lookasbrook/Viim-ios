#!/usr/bin/env node
// Crée les modèles WhatsApp requis par backend/src/services/newagent.js (mode Meta natif).
//
// Prérequis :
//   - la passerelle NEwAGENT-IA / l'app Meta « Agent IA » envoie depuis un WABA connu ;
//   - un token avec l'accès `whatsapp_business_management` sur ce WABA.
//
// Usage :
//   WABA_ID=... META_TOKEN=... node backend/scripts/create-whatsapp-templates.mjs          # dry-run
//   WABA_ID=... META_TOKEN=... node backend/scripts/create-whatsapp-templates.mjs --apply  # crée
//
// GRAPH_VERSION par défaut v21.0. Les modèles sont créés en statut PENDING ; l'approbation Meta
// est asynchrone. Tant qu'ils ne sont pas APPROVED, aucun envoi de modèle ne partira.

const WABA_ID = process.env.WABA_ID;
const META_TOKEN = process.env.META_TOKEN;
const GRAPH_VERSION = process.env.GRAPH_VERSION ?? "v21.0";
const APPLY = process.argv.includes("--apply");

const MAPS_URL = "https://maps.google.com/?q={{1}}";
const EXAMPLE_QUERY = "12.371800,-1.519600";
const EXAMPLE_COORDS = "12.371800, -1.519600";

const templates = [
  {
    name: "viim_alert_test",
    language: "fr",
    category: "UTILITY",
    components: [
      {
        type: "BODY",
        text:
          "Test Viim : votre canal WhatsApp d'alerte famille est actif. " +
          "Si vous recevez ce message, tout fonctionne. Vous pouvez ignorer ce test."
      }
    ]
  },
  {
    name: "viim_collision_alert",
    language: "fr",
    category: "UTILITY",
    components: [
      {
        type: "BODY",
        text:
          "Alerte Viim : collision signalée pour {{1}}. " +
          "Derniere position connue : {{2}}. Ouvrez la carte pour localiser et porter secours.",
        example: { body_text: [["Guy", EXAMPLE_COORDS]] }
      },
      {
        type: "BUTTONS",
        buttons: [
          {
            type: "URL",
            text: "Voir sur la carte",
            url: MAPS_URL,
            example: [`https://maps.google.com/?q=${EXAMPLE_QUERY}`]
          }
        ]
      }
    ]
  },
  {
    name: "viim_location_share",
    language: "fr",
    category: "UTILITY",
    components: [
      {
        type: "BODY",
        text: "{{1}} partage sa position avec vous via Viim. Position : {{2}}.",
        example: { body_text: [["Guy", EXAMPLE_COORDS]] }
      },
      {
        type: "BUTTONS",
        buttons: [
          {
            type: "URL",
            text: "Voir sur la carte",
            url: MAPS_URL,
            example: [`https://maps.google.com/?q=${EXAMPLE_QUERY}`]
          }
        ]
      }
    ]
  }
];

async function main() {
  if (!APPLY) {
    console.log("DRY-RUN — ajouter --apply pour créer. Charges utiles :\n");
    for (const template of templates) {
      console.log(JSON.stringify(template, null, 2));
    }
    console.log(
      `\n${templates.length} modèles. Cible : POST https://graph.facebook.com/${GRAPH_VERSION}/<WABA_ID>/message_templates`
    );
    return;
  }

  if (!WABA_ID || !META_TOKEN) {
    console.error("WABA_ID et META_TOKEN sont requis avec --apply.");
    process.exit(1);
  }

  const endpoint = `https://graph.facebook.com/${GRAPH_VERSION}/${WABA_ID}/message_templates`;
  let failures = 0;

  for (const template of templates) {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${META_TOKEN}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(template)
    });
    const body = await response.json().catch(() => ({}));

    if (response.ok) {
      console.log(`OK   ${template.name} -> id=${body.id ?? "?"} status=${body.status ?? "?"}`);
    } else {
      failures += 1;
      const detail = body?.error?.message ?? `HTTP ${response.status}`;
      console.error(`FAIL ${template.name} -> ${detail}`);
    }
  }

  if (failures > 0) {
    process.exit(1);
  }
  console.log("\nModèles soumis. Suivre l'approbation dans WhatsApp Manager ou via le webhook message_template_status_update.");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
