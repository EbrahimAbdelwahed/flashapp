/* FlashApp — landing di prelancio.
   Caricato nell'<head> senza defer: la classe .js deve esserci prima del
   primo paint, altrimenti le sezioni animate lampeggiano. */

const DEADLINE = new Date("2026-08-18T23:59:59+02:00");
const SOURCES = ["Reddit", "TikTok", "Instagram", "Passaparola", "Altro"];

if (window.IntersectionObserver) document.documentElement.classList.add("js");

document.addEventListener("DOMContentLoaded", () => {
  /* --- countdown ------------------------------------------------- */
  const cd = document.getElementById("cd");
  const tick = () => {
    const ms = DEADLINE - Date.now();
    if (ms <= 0) {
      cd.textContent = "";
      return;
    }
    const d = Math.floor(ms / 864e5);
    const h = Math.floor(ms / 36e5) % 24;
    const m = Math.floor(ms / 6e4) % 60;
    cd.textContent = d > 0 ? `Mancano ${d}g ${h}h ${m}m` : `Mancano ${h}h ${m}m`;
  };
  tick();
  setInterval(tick, 30000);

  /* --- header ---------------------------------------------------- */
  const hdr = document.getElementById("hdr");
  addEventListener("scroll", () => hdr.classList.toggle("is-stuck", scrollY > 8), {
    passive: true,
  });

  /* --- reveal ---------------------------------------------------- */
  const reveals = document.querySelectorAll(".reveal");
  if (window.IntersectionObserver) {
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) {
            e.target.classList.add("in");
            io.unobserve(e.target);
          }
        }
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
    );
    reveals.forEach((el, i) => {
      el.style.transitionDelay = `${Math.min(i % 4, 3) * 60}ms`;
      io.observe(el);
    });
    // Rete di sicurezza: se l'observer non scatta (tab in background, browser
    // particolari) dopo 2,5s la pagina si mostra comunque per intero.
    setTimeout(() => reveals.forEach((el) => el.classList.add("in")), 2500);
  }

  /* --- form ------------------------------------------------------ */
  const form = document.getElementById("waitlist");
  const card = form.closest(".card-form");
  const note = document.getElementById("note");
  const submit = document.getElementById("submit");

  const say = (msg, kind) => {
    note.textContent = msg;
    note.className = "formnote " + kind;
  };

  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    note.className = "formnote";

    const email = form.email.value.trim();
    const source = form.querySelector('input[name="source"]:checked');

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
      say("Controlla l'indirizzo email: sembra incompleto.", "err");
      form.email.focus();
      return;
    }
    if (!source || !SOURCES.includes(source.value)) {
      say("Dimmi anche dove mi hai conosciuto — mi serve per capire dove continuare a pubblicare.", "err");
      return;
    }

    submit.disabled = true;
    const label = submit.textContent;
    submit.textContent = "Un attimo…";

    try {
      const res = await fetch("/api/subscribe", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email,
          source: source.value,
          landing: location.pathname + location.search,
        }),
      });

      if (res.status === 429) {
        submit.disabled = false;
        submit.textContent = label;
        say("Troppi tentativi da questa connessione. Riprova tra un'ora.", "warn");
        return;
      }
      if (!res.ok) throw new Error(String(res.status));

      card.classList.add("sent");
      form.classList.add("sent");
    } catch {
      submit.disabled = false;
      submit.textContent = label;
      say("Non sono riuscito a registrarti — riprova tra un attimo.", "err");
    }
  });
});
