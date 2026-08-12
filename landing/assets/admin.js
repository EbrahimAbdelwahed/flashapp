/* FlashApp — dashboard iscritti.
   Nessun dato è nel documento: la tabella arriva da /api/list, che risponde
   solo con un cookie di sessione valido. */

document.addEventListener("DOMContentLoaded", () => {
  const gate = document.getElementById("gate");
  const dash = document.getElementById("dash");
  const loginForm = document.getElementById("loginform");
  const loginBtn = document.getElementById("loginbtn");
  const loginMsg = document.getElementById("loginmsg");
  const passwordInput = document.getElementById("password");
  const rows = document.getElementById("rows");
  const stats = document.getElementById("stats");
  const empty = document.getElementById("empty");

  const show = (el) => el.removeAttribute("hidden");
  const hide = (el) => el.setAttribute("hidden", "");

  const formatDate = (iso) =>
    new Date(iso).toLocaleString("it-IT", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });

  function render(data) {
    stats.replaceChildren();
    const tot = document.createElement("div");
    tot.className = "stat tot";
    tot.innerHTML = "<b></b><span>iscritti in totale</span>";
    tot.querySelector("b").textContent = data.total;
    stats.append(tot);

    for (const { source, count } of data.bySource) {
      const el = document.createElement("div");
      el.className = "stat";
      el.innerHTML = "<b></b><span></span>";
      el.querySelector("b").textContent = count;
      el.querySelector("span").textContent = source;
      stats.append(el);
    }

    rows.replaceChildren();
    for (const r of data.rows) {
      const tr = document.createElement("tr");
      const email = document.createElement("td");
      email.className = "email";
      email.textContent = r.email;

      const source = document.createElement("td");
      const pill = document.createElement("span");
      pill.className = "pill";
      pill.textContent = r.source;
      source.append(pill);

      const landing = document.createElement("td");
      landing.textContent = r.landing || "—";

      const when = document.createElement("td");
      when.textContent = formatDate(r.created_at);

      tr.append(email, source, landing, when);
      rows.append(tr);
    }

    empty.toggleAttribute("hidden", data.rows.length > 0);
    document.getElementById("table").toggleAttribute("hidden", data.rows.length === 0);
  }

  async function load() {
    const res = await fetch("/api/list", { credentials: "same-origin" });
    if (res.status === 401) {
      passwordInput.focus();
      return false;
    }
    if (!res.ok) throw new Error(String(res.status));

    render(await res.json());
    hide(gate);
    show(dash);
    return true;
  }

  loginForm.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    loginMsg.textContent = "";
    loginBtn.disabled = true;

    try {
      const res = await fetch("/api/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        body: JSON.stringify({ password: passwordInput.value }),
      });

      if (res.status === 429) {
        loginMsg.textContent = "Troppi tentativi. Riprova tra un quarto d'ora.";
        return;
      }
      if (res.status === 401) {
        loginMsg.textContent = "Password errata.";
        passwordInput.select();
        return;
      }
      if (!res.ok) {
        // Errore di configurazione, non di password: mostralo per intero,
        // altrimenti si finisce a riprovare la password all'infinito.
        const body = await res.json().catch(() => ({}));
        loginMsg.textContent =
          body.detail || `Errore del server (${res.status}). Controlla i log su Vercel.`;
        return;
      }

      passwordInput.value = "";
      await load();
    } catch {
      loginMsg.textContent = "Errore di rete. Riprova.";
    } finally {
      loginBtn.disabled = false;
    }
  });

  document.getElementById("logout").addEventListener("click", async () => {
    await fetch("/api/logout", { method: "POST", credentials: "same-origin" });
    location.reload();
  });

  document.getElementById("csv").addEventListener("click", () => {
    location.href = "/api/export";
  });

  // Se la sessione è ancora valida la dashboard prende il posto del login.
  load().catch(() => {});
});
