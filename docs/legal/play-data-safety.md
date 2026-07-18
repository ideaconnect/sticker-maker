# Google Play Data Safety — form answers

This is the source of truth for completing the **Data safety** section in Play
Console. It is written to be **consistent with the privacy policy**
(`privacy-policy.md`). Sticker Maker processes everything on‑device and collects
nothing, so nearly every answer is "No".

> When the Console wording changes, update this file first, then mirror it into
> the form — the two must always match.

## Data collection and security

| Question | Answer |
|----------|--------|
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data collected by your app encrypted in transit? | N/A — no data is collected or transmitted |
| Do you provide a way for users to request that their data is deleted? | N/A — no data is collected |

Because the first answer is **No**, the Console will not ask you to enumerate
data types. The tables below record *why* each category is "No", so the answer is
defensible if reviewed.

## Data types — all "Not collected"

| Category | Collected? | Why |
|----------|-----------|-----|
| Location | No | The app never requests or reads location. |
| Personal info (name, email, etc.) | No | No accounts, no sign‑in, no forms. |
| Financial info | No | Purchase is handled by Google Play billing, not the app. |
| Health & fitness | No | N/A. |
| Messages | No | N/A. |
| Photos / videos | **Not collected** | Photos are read **locally** to make a sticker and never uploaded. Selecting a photo for on‑device processing is not "collection" under Play's definition. |
| Audio files | No | N/A. |
| Files & docs | No | Only the app's own project files, in private storage. |
| Calendar | No | N/A. |
| Contacts | No | N/A. |
| App activity / interactions | No | No analytics SDK; no interaction logging. |
| Web browsing | No | N/A. |
| App info & performance (crash logs, diagnostics) | No | No crash‑reporting or diagnostics SDK. |
| Device or other IDs | No | No advertising ID, no device‑ID collection. |

## Ads and tracking

- Contains ads: **No**
- Uses an advertising ID: **No**
- Shares data with third parties for advertising/analytics: **No**

## Notes for the reviewer

- The **system share sheet** hands an exported sticker to an app the *user*
  chooses; Sticker Maker does not transmit it anywhere itself.
- **Google ML Kit** (Android background removal) may download an on‑device model
  via Google Play Services. That is a model download for **local inference** —
  user photos are not sent to Google. This is infrastructure, not user‑data
  collection, and does not change any answer above.

## Consistency checklist (before publishing)

- [ ] Privacy policy URL entered in Play Console matches the hosted
      `privacy-policy.md`.
- [ ] "Data collected" = No, matching the policy's plain statement.
- [ ] No ads / no advertising ID, matching the policy.
- [ ] In‑app **About → Privacy policy** shows the same URL.
