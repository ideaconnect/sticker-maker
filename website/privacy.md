---
layout: page
title: Privacy &amp; Cookies
eyebrow: Two different things, kept apart
lead: >-
  The Sticker Maker app collects nothing: no accounts, no analytics, no uploads.
  Your photos never leave your phone. This website is separate. It is a static
  page that loads Google Analytics only if you accept it, and nothing before that.
description: >-
  Sticker Maker privacy policy. The app collects, stores and transmits nothing.
  The website loads analytics only after explicit consent.
---

**Last updated** - app policy: **18 July 2026** · website section: **20 July 2026**

<div class="legal-toc">
  <p class="legal-toc-title">On this page</p>
  <ol>
    <li><a href="#controller">Who is responsible</a></li>
    <li><a href="#short-version">The short version</a></li>
    <li><a href="#app-processing">What the app processes, and where</a></li>
    <li><a href="#permissions">Permissions</a></li>
    <li><a href="#sharing">Sharing a sticker</a></li>
    <li><a href="#plain-statement">A plain statement</a></li>
    <li><a href="#children">Children</a></li>
    <li><a href="#components">Third-party components in the app</a></li>
    <li><a href="#website">This website</a></li>
    <li><a href="#rights">Your rights</a></li>
    <li><a href="#changes">Changes to this policy</a></li>
    <li><a href="#contact">Contact</a></li>
  </ol>
</div>

This page covers two separate things, and keeps them apart:

- **The app** - Sticker Maker on your phone. It collects **nothing at all**. Sections 1-8.
- **This website** - the pages you are reading. It can load analytics, but only
  after you press Accept. Section 9.

## Who is responsible
{: #controller }

The data controller for this website, and the maker of the app, is
**IDCT Bartosz Pachołek** (idct.tech):

> **IDCT Bartosz Pachołek**
> Kaszubska 12/8C
> 70-403 Szczecin, Poland
> NIP (VAT EU): PL7642542255

Contact: **[{{ site.email }}](mailto:{{ site.email }})** or the
[contact page]({{ '/contact/' | relative_url }}).

## The short version
{: #short-version }

**Sticker Maker does not collect, store, or transmit any personal data.** Everything
you do in the app happens **on your device**. We have no servers that receive your
photos or your usage, no accounts, no analytics, no advertising, and no third-party
trackers. It is a paid app with every feature included. There is nothing to sell,
and no reason to collect your data.

## What the app processes, and where
{: #app-processing }

| What | Where it happens | Leaves your device? |
|------|------------------|---------------------|
| Photos you import | On your device | **No** |
| AI background removal | On your device (Google ML Kit on Android / bundled model) | **No** |
| Text, bubbles, stickers, animation frames | On your device | **No** |
| Your saved projects and packs | Stored locally in the app's private storage | **No** |
| Exporting / sharing a sticker | You choose the destination app via the system share sheet | Only when **you** share it |

The AI that removes backgrounds runs entirely on your device. Your photos are never
uploaded to us or to any third party for processing.

## Permissions
{: #permissions }

- **Photos / Media** - so you can pick an image to turn into a sticker. The image is
  read locally and never uploaded.
- **Camera** (if you take a photo in-app) - used locally to capture an image.

You can revoke these in your system settings at any time. The app then won't be
able to import new photos until you grant them again.

## Sharing a sticker
{: #sharing }

When you export a sticker, Android's share sheet lets you send it to another app:
WhatsApp, Telegram, your gallery, and so on. At that point the sticker is handled by
the app **you** picked, under **its** privacy policy. Sticker Maker itself does not
transmit anything.

## A plain statement
{: #plain-statement }

About the app:

- We do **not** collect any data.
- We do **not** share any data with third parties.
- We do **not** use analytics or crash-reporting SDKs.
- We do **not** show ads or use advertising identifiers.
- There are **no** user accounts and **no** sign-in.

## Children
{: #children }

Sticker Maker does not knowingly collect any data from anyone, including children,
because it does not collect data at all.

## Third-party components in the app
{: #components }

The app bundles open-source components (fonts, the on-device AI model, and media
libraries). These run locally and do not send your data anywhere. Their license
notices are available in the app under **About → Open-source licenses**.

On Android, background removal may use Google ML Kit, which can download its
on-device model through Google Play services. That is a model download for local
processing. Your photos are not sent to Google for inference. See
[Google's ML Kit terms](https://developers.google.com/ml-kit/terms).

## This website
{: #website }

Everything above is about the app. This section is only about
**idct.tech/sticker-maker**.

### How the site is served

The site is a **static** site: plain HTML, CSS, two small JavaScript files (one
for scroll effects, one for the cookie banner), and self-hosted fonts. There is no database, no login, and no server-side code of ours.
It is hosted on **GitHub Pages**. GitHub serves the files and, like any web host,
processes the request data that reaching a server necessarily involves (IP address,
time, requested URL, user agent) for delivery, security, and abuse prevention. See
the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
We have no access to those logs.

### Analytics, and what is running today

The site is built with a **prior-consent** design: Google Analytics 4 is **never**
loaded before you press **Accept** in the cookie banner. If you press Reject, or
ignore the banner, nothing is requested from Google and no analytics cookies are
set. The site works the same either way.

To be precise about the current state: **no measurement ID is configured in this
site's build, so Google Analytics is not loaded at all right now, not even if you
accept.** Pressing Accept today records your preference and closes the banner,
nothing more. The paragraphs below describe what would happen *if* analytics is ever
switched on. This page will keep saying which of the two is true.

If it is switched on, it would measure aggregate, anonymous usage (pages viewed,
rough geography, device and browser type, referring links) to understand which
pages are useful. Either way we do **not**:

- serve ads or use advertising cookies;
- track you across other websites;
- sell or share your data with third parties for marketing;
- attempt to identify you personally.

### Cookies and local storage

| What | Set when | Purpose | Retention |
| --- | --- | --- | --- |
| `stickermaker-consent` (`localStorage`) | You press Accept **or** Reject | Remembers your choice so the banner doesn't reappear every visit | Re-asked after **180 days** |
| `_ga` (cookie) | Only if analytics is enabled **and** you accepted | Distinguishes anonymous visitors | ~2 years |
| `_ga_<ID>` (cookie) | Only if analytics is enabled **and** you accepted | Keeps the analytics session state | ~2 years |

The `stickermaker-consent` entry is a small piece of JSON holding your choice
(`granted` or `denied`), the date you made it, and a version number. It is strictly
functional, not analytics, and it stays in your browser, never sent anywhere.
Pressing **Reject** also deletes any `_ga` cookies that a previous Accept had set.

### The contact form

The [contact form]({{ '/contact/' | relative_url }}) is processed by **Web3Forms**,
which receives what you type (your name, your email address, and your message) and
emails it to us. It is protected from spam by **hCaptcha**, whose script loads on the
contact page so the challenge can render. That happens independently of your analytics
choice, because the form cannot be submitted without it. Submitting the form therefore
involves those two services and their own processing. See the
[Web3Forms privacy policy](https://web3forms.com/privacy) and the
[hCaptcha privacy policy](https://www.hcaptcha.com/privacy). To be precise about the
current state again: **the form is switched off in this site's build pending its
service key, so the contact page offers a plain email link and loads neither
service.** If you'd rather not use the form, email
**[{{ site.email }}](mailto:{{ site.email }})** directly.

We keep contact emails for as long as it takes to answer you and to keep a record of
the conversation, then delete them.

### Legal basis

Analytics, if enabled, is processed **only on the basis of your consent**
(GDPR Art. 6(1)(a)), which you can withdraw at any time. Withdrawing consent does not
affect processing that already happened. Answering your message is processing on the
basis of our legitimate interest in replying to you, or of taking steps at your
request (GDPR Art. 6(1)(f) and 6(1)(b)). Spam protection on the form is a legitimate
interest in keeping the site usable.

### International transfer

If analytics is enabled and you accept, data is processed by Google LLC in the United
States; Google is certified under the EU-U.S. Data Privacy Framework, which the
transfer relies on, with Standard Contractual Clauses as a fallback safeguard. Google
Analytics 4 does not store IP addresses. Web3Forms and hCaptcha likewise operate
outside the EEA and rely on their own transfer safeguards.

### Your choices

- **Accept** or **Reject** in the banner. Reject keeps analytics fully off.
- Change your mind at any time via **Cookie preferences** in the footer, or by
  clearing this site's data in your browser.
- Install Google's [Analytics opt-out add-on](https://tools.google.com/dlpage/gaoptout).

## Your rights
{: #rights }

Under the GDPR you have the right to access, rectify, erase, restrict or object to
processing of your data, the right to data portability, the right to withdraw consent,
and the right to lodge a complaint with your data-protection supervisory authority
(in Poland, the [UODO](https://uodo.gov.pl/)). To exercise any of these, use the
[contact page]({{ '/contact/' | relative_url }}).

For **the app** there is nothing to exercise them against. We hold no data about you,
so there is nothing to access, correct, export or erase.

## Changes to this policy
{: #changes }

If this policy ever changes, the updated version will be posted at this URL with a new
"Last updated" date. Because the app collects no data, we do not expect material
changes to the app half of it.

## Contact
{: #contact }

Questions about privacy? Email **[{{ site.email }}](mailto:{{ site.email }})** or use
the [contact page]({{ '/contact/' | relative_url }}).
