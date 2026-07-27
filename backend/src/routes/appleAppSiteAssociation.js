const association = Object.freeze({
  applinks: {
    apps: [],
    details: [{
      appID: "MJJ6A56JHS.com.yamstack.viim",
      components: [{ "/": "/join/*" }]
    }]
  }
});

export function appleAppSiteAssociation(_request, response) {
  response
    .set("Cache-Control", "public, max-age=3600")
    .type("application/json")
    .send(association);
}
