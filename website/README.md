# Sticker Maker marketing website

The public website for the **Sticker Maker** app - landing page, features,
privacy, terms, and a contact form. It is a self-contained **Jekyll** site
living in this subfolder so it deploys to GitHub Pages independently of the app
source.

**Custom layouts + hand-written CSS only** - no gem theme, no plugins, no CDN,
no webfont service. It builds on GitHub Pages' stock Jekyll with no extra
configuration, and every asset it loads comes from this folder.

> **This app is paid and closed source.** There is no public repository, no
> issue tracker and no chat community, so nothing on the site links to one and
> there is deliberately no `repo:` / `discord:` / `sponsor:` key in
> `_config.yml`. If you are adding a page, do not introduce one.

## Before going live

Items 3 to 6 still ship as **placeholders**. Each is a one-line change, and none
of them break the build - they just quietly do nothing, which is exactly why they
are easy to forget.

Items 1 and 2 are **done**. Both are now live, so the contact form renders and
analytics loads after consent. If either is ever cleared again, the guards below
put the site back into its safe state automatically, and the privacy page swaps
to the matching wording on its own - see "Two claims-related rules" further down.

| # | What | Where | Until then |
|---|------|-------|------------|
| 1 | ✅ **Web3Forms access key** - `web3forms_key` | `_config.yml` | **Set.** The contact form renders and posts to Web3Forms with hCaptcha. While the value looked like a placeholder, `contact.md` showed an "email me directly" panel instead, because a form with a placeholder key POSTs happily and silently drops the message. That guard is still in place. |
| 2 | ✅ **Google Analytics ID** - `ga_id` | `_config.yml` | **Set** (`G-14LYCBCVLS`). GA4 loads only after the visitor presses Accept; Reject or no choice means nothing is requested from Google. Emission is still double-gated on `JEKYLL_ENV=production` **and** a non-empty `ga_id`, so local `jekyll serve` never loads analytics. |
| 3 | **Play Store URL** - `playstore` | `_config.yml` | The current value is *constructed* from the applicationId (`tech.idct.stickermaker`), not confirmed against a live listing. Confirm the real URL from the Play Console once the listing is published. Every Play link on the site goes through this key. |
| 4 | **App Store badge** | `_config.yml` (`appstore_status`) + `_layouts/default.html` | iOS has not shipped. The badge renders as a non-interactive `<span class="store-badge soon">`, never a link to an invented URL. When iOS ships, add an `appstore:` URL and flip `appstore_status`. |
| 5 | **Real screenshots** | `assets/img/` + the `hero_art` front matter | There are no app screenshots in the repo, so all product imagery is a hand-built HTML/CSS recreation of the app's screens (`.phone`, `.checker`, `.sticker`, `.toolbar`) using the real design tokens. When real captures exist, pages can switch from `hero_art:` to `hero_image:` - `_layouts/page.html` supports both. |
| 6 | **Have a lawyer read `terms.md`** | `terms.md` | ⚠️ The terms were written by the app's author, not a lawyer. **Get them reviewed before commercial launch** - this is a paid app sold to consumers, and consumer-sales law (statutory withdrawal rights, warranty, liability caps) is not something to improvise. `privacy.md` deserves the same read-through. |

Two claims-related rules for anyone editing copy:

- **Never claim more than the app actually does.** No price (undecided) and no
  shipped iOS. On packs, be precise about the asymmetry: **Add to WhatsApp**
  really does install a finished pack into WhatsApp's own sticker picker
  (`ENABLE_STICKER_PACK` + the `StickerContentProvider`, #46), while
  **Add to Telegram** is a *guided* handoff - the pack is rendered and sent into
  Telegram with a suggested short name for `@Stickers` (#48), not a one-tap
  install. `docs/release/store-listing.md` still carries a pre-#46/#48 note
  saying pack install hasn't landed; that note is stale, the code is the source
  of truth.
- **Keep the app and the website apart** on the privacy page. The *app*
  collects nothing, uploads nothing, has no accounts and no analytics SDK. The
  *website* can use Google Analytics, but only after explicit consent. Blurring
  the two is the one mistake that would actually matter.

## Run locally

Needs Ruby + Bundler (any 3.x). From this folder:

```bash
cd website
bundle install
bundle exec jekyll serve --baseurl ""     # http://localhost:4000/
```

**Why `--baseurl ""`.** `_config.yml` sets `baseurl: "/sticker-maker"` because
the deployed site is a GitHub Pages *project* page served under the org's apex
domain. Locally there is no such prefix, so without the override every
`relative_url` link would point at `http://localhost:4000/sticker-maker/…` and
404. Passing an empty baseurl serves the site at the root instead. Nothing in
the site hard-codes a path - links and assets all go through
`relative_url` / `absolute_url` - so both shapes work.

To check the *deployed* shape instead, drop the flag:
`bundle exec jekyll serve` → <http://localhost:4000/sticker-maker/>.

To produce the exact bytes CI produces:

```bash
JEKYLL_ENV=production bundle exec jekyll build --baseurl "/sticker-maker"
```

(`_site/`, `.jekyll-cache/`, `vendor/` and `Gemfile.lock` are gitignored.)

## Deploy

[`.github/workflows/pages.yml`](../.github/workflows/pages.yml) builds on every
PR touching `website/**` (validation only - PRs never publish) and deploys on
push to `main`.

The site is a GitHub Pages **project page** under the `ideaconnect` org's apex
custom domain, served at **<https://idct.tech/sticker-maker/>**:

- `url: "https://idct.tech"` + `baseurl: "/sticker-maker"` in `_config.yml`
- the workflow passes the matching `--baseurl "/sticker-maker"` - **keep the two
  in sync**
- **no `CNAME` file.** The apex belongs to the org's `ideaconnect.github.io`
  page repo; a project `CNAME` would claim `idct.tech` at its root and fight
  with it. The workflow asserts `_site/CNAME` does not exist, so an accidental
  one fails the build rather than breaking the org page.

**One-time setup:** *Settings → Pages → Source: **GitHub Actions***, and leave
the custom-domain field **blank** (the project inherits the org domain).

## Layout

```
website/
├── _config.yml            # site config, nav, store URLs, ga_id, web3forms_key
├── Gemfile                # jekyll ~> 4.3 only
├── _layouts/
│   ├── default.html       # <head>, nav, footer, consent, JSON-LD
│   └── page.html          # sub-page shell: eyebrow/title/lead + hero_image OR hero_art
├── _includes/
│   ├── analytics.html     # GA4, gated on production AND a non-empty ga_id
│   ├── consent.html       # the cookie banner markup
│   └── icon-*.svg         # inline SVGs (play, apple, mail, sparkle) - no icon font
├── index.html             # landing page (composes its own sections, layout: default)
├── features.md            # what the app does
├── privacy.md             # app privacy + website cookies, kept clearly separate
├── terms.md               # terms of sale/use  ← needs legal review, see above
├── contact.md             # Web3Forms + hCaptcha form (guarded, see below)
├── contact/thank-you.md   # the form's redirect target
├── 404.html               # "This one didn't stick."
├── robots.txt / sitemap.xml   # both hand-written, no plugin; sitemap honours `sitemap: false`
├── tools/build_og_card.py # regenerates assets/img/og-card.png (excluded from the build)
└── assets/
    ├── css/style.css      # the entire design system, one file
    ├── js/site.js         # scroll-reveal + nav state, vanilla, no dependencies
    ├── js/consent.js      # the consent banner + GA gating
    ├── fonts/             # self-hosted TTFs + their OFL licences
    └── img/               # icons, favicons, og-card (see assets/img/README.md)
```

Page conventions, in case you add one:

- Content pages use `layout: page` with `title`, `description`, `eyebrow`,
  `lead`, and optionally `hero_image` **or** `hero_art` (raw HTML for the CSS
  product mocks). With neither, the hero becomes a single full-width column.
- **Every** internal link and asset goes through `{{ '/x/' | relative_url }}`.
  A bare `/features/` is a bug: it breaks under the `/sticker-maker` baseurl.
- Store URLs and the contact address come from `site.*`, never hard-coded.
- `class="reveal"` on a block makes it scroll into view (`assets/js/site.js`);
  a `<noscript>` rule in the layout keeps it visible without JS, and
  `prefers-reduced-motion` disables it entirely.
- Only use classes that exist in `assets/css/style.css`. No `<style>` blocks,
  no inline styles beyond one-off spacing (`style="margin-top:0"`) and the
  documented custom-property hooks (`--bob-delay`, `--fill`, `--tilt`, …).

## Fonts

`assets/fonts/` holds **self-hosted** copies of the two display faces the app
itself uses, taken byte-for-byte from the app's `assets/fonts/`:

| File | Used for |
|------|----------|
| `Fredoka-Variable.ttf` | headings (`--font-head`) |
| `Bangers-Regular.ttf` | sticker captions / display flourishes (`--font-display`) |

Both are licensed under the **SIL Open Font License 1.1**, and the OFL requires
the licence to travel with the font - hence `OFL-Fredoka.txt` and
`OFL-Bangers.txt` sitting next to them. **Do not delete those two text files**,
and do not swap the `@font-face` sources for a Google Fonts URL: it would add a
third-party request on every page load, which is precisely what the consent
banner exists to avoid.

Body text uses the system font stack (`--font-body`) - no download at all.

Only TTFs ship today. If the ~250 KB of font bytes ever matters, generate
`.woff2` siblings (`pip install fonttools brotli`, then
`fonttools ttLib.woff2 compress …`) and add them ahead of the TTF in the
`@font-face` `src:` list - expect roughly a 50-60 % size cut.

## Images and the social card

Everything in `assets/img/` is either copied from the app's branding assets or
generated from them; `assets/img/README.md` records which is which, with
reproduction steps.

The 1200×630 OpenGraph/Twitter card is **generated, not hand-drawn**:

```bash
python website/tools/build_og_card.py        # rewrites website/assets/img/og-card.png
```

It composes the card from repo artefacts (the app icon, the brand gradient, the
two fonts, and the real `icon_foreground.png` dilated into a white die-cut
sticker) and is deterministic - two runs produce identical bytes. Re-run it if
the branding, the tagline or the gradient changes, then commit the result.
`tools/` is in `_config.yml`'s `exclude:` list, so the script never lands in
`_site`.

`tools/optimize_res.py` at the repo root is **not** applicable here: it is
hard-wired to `android/app/src/main/res` and CI only checks that directory.

## Contact form

[`contact.md`](contact.md) does a plain (non-AJAX) `POST` to
[Web3Forms](https://web3forms.com) with hCaptcha - the same setup as the sibling
sites. Submissions reach the form owner's inbox via `access_key`; there is no
server to run. The POST must stay non-AJAX: Web3Forms only honours the
`redirect` field (→ `/contact/thank-you/`) on a normal form submission.

Two things worth knowing:

- The page is **guarded**. While `web3forms_key` still looks like a placeholder
  the form is replaced by a mailto panel, and the hCaptcha script is not loaded
  either. Set the real key and both appear.
- `contact/thank-you.md` carries `sitemap: false` (so it stays out of
  `sitemap.xml`) and a `robots: noindex` front-matter key. `_layouts/default.html`
  renders `page.robots` as `<meta name="robots">` whenever the key is present, so
  the page is excluded from the sitemap and marked noindex.

The hCaptcha script and (post-consent) Google Analytics are the only external
scripts on the entire site.

## Analytics and consent

`assets/js/consent.js` implements a **prior-consent** model: Google Analytics is
injected only after the visitor presses *Accept*, or on a return visit with a
stored, unexpired `granted` choice (localStorage key `stickermaker-consent`,
v1, 180 days). Reject or ignore the banner and nothing ever contacts Google.
Any element with `data-consent-open` (the footer's "Cookie preferences" button)
reopens the banner so a choice can be changed.

This is the *website*. The **app** has no analytics of any kind, no accounts and
no network calls for your photos; `privacy.md` must keep saying so, separately.
