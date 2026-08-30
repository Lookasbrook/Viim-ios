// Texte de l'alerte collision, partagé entre l'envoi immédiat (routes/alerts.js) et la
// cascade différée (collisionEscalationWorker.js) pour éviter toute divergence de formulation.
export function buildCollisionMessage({ driverName, location }) {
  const latitude = Number(location?.latitude);
  const longitude = Number(location?.longitude);
  const mapsUrl = `https://maps.google.com/?q=${latitude},${longitude}`;
  return [
    `Alerte Viim : collision confirmée pour ${driverName}.`,
    `Position : ${latitude.toFixed(6)}, ${longitude.toFixed(6)}.`,
    mapsUrl
  ].join(" ");
}
