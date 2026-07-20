/* Cookie-consent controller - prior-consent model for Google Analytics 4.
   - Banner shows on first visit, or when a stored choice is missing / expired
     (>180 days) / from an older policy version → consent is re-solicited.
   - Accept  => inject & start GA (window.loadGoogleAnalytics, defined in the head
                only in production AND only when site.ga_id is set) and persist
                {choice:'granted', ts, v}. While ga_id is empty - the shipping
                state - that function does not exist and Accept simply records
                the choice and closes the banner. That is intentional, not a bug.
   - Reject  => never load GA; if it was already loaded this session, deny + delete
                the _ga cookies; persist {choice:'denied', ts, v}.
   - Any [data-consent-open] element (footer "Cookie preferences") re-opens the
     banner and moves focus into it (withdraw / change). */
(function () {
  "use strict";
  var KEY = "stickermaker-consent";
  var VERSION = 1;
  var MAX_AGE = 180 * 24 * 60 * 60 * 1000; // re-ask after 180 days
  var banner = document.getElementById("consent-banner");

  function read() {
    try {
      var c = JSON.parse(localStorage.getItem(KEY) || "null");
      if (!c || c.v !== VERSION || (Date.now() - c.ts) > MAX_AGE) return null;
      return c;
    } catch (e) { return null; }
  }
  function write(choice) {
    try { localStorage.setItem(KEY, JSON.stringify({ choice: choice, ts: Date.now(), v: VERSION })); } catch (e) {}
  }
  function hide() { if (banner) banner.classList.add("hidden"); }
  function show() { if (banner) banner.classList.remove("hidden"); }

  function clearGACookies() {
    var names = ["_ga"];
    if (window.__gaId) names.push("_ga_" + window.__gaId.replace(/^G-/, ""));
    names.forEach(function (n) {
      document.cookie = n + "=; Max-Age=0; path=/";
      document.cookie = n + "=; Max-Age=0; path=/; domain=." + location.hostname;
    });
  }

  function decide(choice) {
    var granted = choice === "granted";
    write(granted ? "granted" : "denied");
    if (granted) {
      // No-ops gracefully when analytics was never emitted (ga_id empty, or a
      // non-production build).
      if (typeof window.loadGoogleAnalytics === "function") window.loadGoogleAnalytics();
    } else {
      if (typeof window.gtag === "function") window.gtag("consent", "update", { analytics_storage: "denied" });
      clearGACookies();
    }
    hide();
  }

  var accept = document.getElementById("consent-accept");
  var reject = document.getElementById("consent-reject");
  if (accept) accept.addEventListener("click", function () { decide("granted"); });
  if (reject) reject.addEventListener("click", function () { decide("denied"); });

  // Footer "Cookie preferences" (or any [data-consent-open]) re-opens the banner.
  document.querySelectorAll("[data-consent-open]").forEach(function (el) {
    el.addEventListener("click", function (e) {
      e.preventDefault();
      show();
      if (reject) reject.focus(); // user-initiated reopen → move focus into the banner (a11y)
    });
  });

  if (!read()) show(); // first visit, or consent absent / expired / versioned-out
})();
