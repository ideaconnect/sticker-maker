---
layout: page
title: Contact
eyebrow: Say hello
lead: A bug, a feature idea, a question before you buy, or a sticker you're proud of? Send a message and it lands in my inbox.
description: Get in touch about Sticker Maker - questions, bug reports, and feature ideas.
# There are no app screenshots in this repo, so the hero art is a CSS
# recreation of the app's "Send to" sheet, re-labelled for this page. Only
# in-flow phone classes are used here: `.sticker` is absolutely positioned
# inside `.page-hero-art`, so the two floating stickers sit outside the phone.
hero_art: >-
  <div class="phone" role="img" aria-label="A phone showing a Say hello screen listing what lands well: a bug with your phone model, a feature you wish existed, a question before you buy, or a sticker you're proud of.">
  <div class="phone-screen">
  <span class="phone-notch"></span>
  <div class="phone-bar">
  <div>
  <p class="phone-bar-title">Say hello</p>
  <p class="phone-bar-sub">Sticker Maker</p>
  </div>
  <span class="phone-cta sm">Send</span>
  </div>
  <div class="phone-body">
  <p class="phone-panel-title">What lands well</p>
  <div class="target is-active"><span aria-hidden="true">🐞</span> A bug, with your phone model <span class="dotmark"></span></div>
  <div class="target"><span aria-hidden="true">💡</span> A feature you wish existed <span class="dotmark"></span></div>
  <div class="target"><span aria-hidden="true">❓</span> A question before you buy <span class="dotmark"></span></div>
  <div class="target"><span aria-hidden="true">🐶</span> A sticker you're proud of <span class="dotmark"></span></div>
  <span class="toast">Straight to my inbox</span>
  </div>
  <div class="phone-panel">
  <p class="phone-panel-title">One human reads it</p>
  <p>No ticket queue, no bot. Usually a reply within a few days.</p>
  </div>
  </div>
  </div>
  <span class="sticker caption sticker-tilt sticker-float pos-tr" aria-hidden="true">Hi!</span>
  <span class="sticker round sticker-tilt sticker-float pos-bl" style="--bob-delay:-2.2s" aria-hidden="true">💬</span>
---

{%- comment -%}
  The Web3Forms access key ships as a placeholder (see _config.yml). A form with
  a placeholder key POSTs happily and then silently drops the message, which is
  worse than no form at all. Guard on it and offer a plain mailto instead
  until the real key is set. `contains` catches the shipped REPLACE-ME value;
  the empty test catches someone blanking the key.
{%- endcomment -%}
{%- assign w3f = site.web3forms_key | default: "" -%}
{%- assign form_ready = true -%}
{%- if w3f == "" or w3f contains "REPLACE" -%}{%- assign form_ready = false -%}{%- endif -%}

<div class="contact-grid">
  <div class="reveal">
    <h2 style="margin-top:0">Other ways to reach me</h2>
    <ul>
      <li><b>Email:</b> <a href="mailto:{{ site.email }}">{{ site.email }}</a> - the fastest route, and the one I can reply to properly.</li>
      <li><b>Web:</b> <a href="{{ site.author_url }}">idct.tech</a>, the rest of what I build.</li>
      <li><b>Store reviews:</b> always appreciated, but a poor place for bugs. I can't ask you a follow-up question there or send you a fix, so a review that says "crashes on export" can't go anywhere. Email me and it can.</li>
    </ul>

    <p class="muted">Sticker Maker is a paid app and its source is closed, so there's no public issue tracker and no chat server. Email is it, and it's read by the person who wrote the app. No ticket queue, no bot. Usually a reply within a few days.</p>

    <h3>Reporting a bug</h3>
    <p class="muted">Three lines is plenty. What you were doing, what you expected, and what happened instead. If you can, add your phone model and Android version. Cut-out quality and export speed both depend on the device.</p>

    <p class="muted">Please don't attach anything you wouldn't want to email. The app never uploads your photos, but a message to me is a normal email and travels like one.</p>
  </div>

{% if form_ready %}
  <form class="contact-form reveal" action="https://api.web3forms.com/submit" method="POST">
    <input type="hidden" name="access_key" value="{{ site.web3forms_key }}">
    <input type="hidden" name="subject" value="New message from the Sticker Maker website">
    <input type="hidden" name="from_name" value="Sticker Maker website">
    <input type="hidden" name="redirect" value="{{ '/contact/thank-you/' | absolute_url }}">
    <input type="checkbox" name="botcheck" hidden tabindex="-1" autocomplete="off">

    <div class="field">
      <label for="name">Name</label>
      <input type="text" name="name" id="name" placeholder="Your name" required>
    </div>

    <div class="field">
      <label for="email">Email</label>
      <input type="email" name="email" id="email" placeholder="you@example.com" required>
    </div>

    <div class="field">
      <label for="message">Message</label>
      <textarea name="message" id="message" rows="5" placeholder="What's on your mind?" required></textarea>
    </div>

    <div class="h-captcha" data-sitekey="50b2fe65-b00b-4b9e-ad62-3ba471098be2"></div>

    <button type="submit" class="btn btn-primary btn-block">{% include icon-mail.svg %} Send message</button>

    <p class="form-note">Sending this form hands your name, email and message to <a href="https://web3forms.com" rel="noopener">Web3Forms</a>, which relays it to my inbox. The spam check is <a href="https://www.hcaptcha.com" rel="noopener">hCaptcha</a>. Both are third parties and both see the submission. That applies to the website, not the app; the <a href="{{ '/privacy/' | relative_url }}">privacy page</a> spells out the difference.</p>
  </form>
{% else %}
  <div class="contact-form reveal">
    <h2 style="margin-top:0">The form isn't wired up yet</h2>
    <p class="muted">This site's contact form is waiting on its form-service key, so it's switched off rather than dropping messages. Use email instead:</p>
    <p><a class="btn btn-primary btn-block" href="mailto:{{ site.email }}?subject=Sticker%20Maker">{% include icon-mail.svg %} Email {{ site.email }}</a></p>
    <p class="form-note">It's the same inbox. Nothing on this page is sent anywhere until you press send in your own mail app.</p>
  </div>
{% endif %}
</div>

{% if form_ready %}
<!-- Standard (non-JS) POST so Web3Forms honours the `redirect` field above and
     sends the visitor to /contact/thank-you/. hCaptcha renders via its own API
     with the Web3Forms shared site key (the AJAX client script would ignore the
     redirect). This is one of only two external scripts on the whole site. The
     other is Google Analytics, which loads only after consent. -->
<script src="https://js.hcaptcha.com/1/api.js" async defer></script>
{% endif %}
