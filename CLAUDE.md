## Outillage MCP Meta

Le dépôt déclare le serveur MCP `meta_developer_tools` (`.mcp.json`, `.cursor/mcp.json`) pour
inspecter l'app Meta « Agent IA » et les webhooks WhatsApp. Avant de l'utiliser ou de toucher au
canal WhatsApp, lire [architecture/meta-mcp-et-whatsapp.md](architecture/meta-mcp-et-whatsapp.md) :
architecture d'envoi via la passerelle NEwAGENT-IA, règle de portée `Read` par défaut, et état de
l'implémentation WhatsApp (modèles approuvés, webhook entrant, cascade des contacts, opt-in).

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec
