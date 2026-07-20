---
layout: page
title: Message sent
eyebrow: Thank you
lead: That's on its way to my inbox. One human reads every message, so give it a few days. If it's a bug, I may write back asking which phone you're on.
description: Your message to Sticker Maker was sent.
permalink: /contact/thank-you/
# Landing page for the Web3Forms redirect, not a page anyone should find in a
# search result: keep it out of sitemap.xml.
sitemap: false
# `_layouts/default.html` renders this as <meta name="robots">, belt and braces
# alongside the sitemap exclusion above, so the Web3Forms redirect target does
# not turn up in search results.
robots: noindex
---

Nothing was uploaded from the app to get here, and nothing about you is stored on
this site. The message went to my email.

If you sent a sticker: thank you, that's the best kind of mail.

<div class="cta-row">
  <a class="btn btn-primary" href="{{ '/' | relative_url }}">Back home</a>
  <a class="btn btn-ghost" href="{{ '/features/' | relative_url }}">See what it can do</a>
</div>

<p class="form-note">Didn't mean to send that, or need to add something? Email
<a href="mailto:{{ site.email }}">{{ site.email }}</a> - same inbox.</p>
