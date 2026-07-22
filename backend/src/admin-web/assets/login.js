const form = document.querySelector("#login-form");
const button = document.querySelector("#login-button");
const errorBox = document.querySelector("#login-error");

form?.addEventListener("submit", async (event) => {
  event.preventDefault();
  errorBox.hidden = true;
  button.disabled = true;
  button.textContent = "Vérification…";

  try {
    const response = await fetch("/admin/api/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        username: form.elements.username.value,
        password: form.elements.password.value
      })
    });

    if (response.ok) {
      window.location.replace("/admin");
      return;
    }

    const body = await response.json().catch(() => ({}));
    const messages = {
      invalid_credentials: "Identifiant ou mot de passe incorrect.",
      too_many_attempts: "Trop de tentatives. Réessayez dans quelques minutes.",
      admin_not_configured: "L’accès admin n’est pas encore configuré sur le serveur."
    };
    throw new Error(messages[body.error] ?? "Connexion momentanément indisponible.");
  } catch (error) {
    errorBox.textContent = error.message;
    errorBox.hidden = false;
  } finally {
    button.disabled = false;
    button.textContent = "Ouvrir le poste de contrôle";
  }
});
