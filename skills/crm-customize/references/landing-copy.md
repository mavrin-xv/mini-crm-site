# Landing page copy for a local service business

The page has one job: get a phone number from someone who needs the service this week.

## Structure that works
1. **Headline**: the service and the place, in the customer's words. "House cleaning in North Park, booked this week." Not the company name.
2. **One line of proof** you can back up: years in business, number of jobs done, insured, a guarantee. Use only real numbers.
3. **The form, above the fold on a phone.** Name, phone, service, optional date, optional message. Every extra required field costs leads.
4. **What happens next**: "We call you back within 15 minutes during work hours." Only promise what the alerts and the operator can deliver. The late-lead alert exists so this promise holds.
5. **Price range or "from" price** if you can. People who see a range and still submit are better leads.
6. **Three to five short reviews** with first name and area, real only.
7. **Phone number as a tap-to-call link** for people who would rather call. Mark those leads as `source: phone` on the board when you add them by hand.

## Form rules
- Phone is required and is the dedup key. Email is optional (`FORM.requireEmail`).
- Keep the hidden `website` input. Bots fill it; people never see it. The server drops those silently.
- Keep the `utm_*` hidden inputs and the small script that fills them. Without them the report cannot say which ad or post brought the lead.
- The success message appears only after the server answers `ok:true`. Never show "Thanks!" before the save is confirmed.
- One submit button, disabled while sending, so a double tap does not send twice. The server also dedups within `FORM.dedupWindowMin` minutes.

## Turnstile (when spam starts)
Honeypot and rate limit stop most bots. If spam still gets through:
1. Cloudflare dashboard, Turnstile, add a widget for your domain. You get a site key and a secret key.
2. Uncomment the Turnstile script tag and the `cf-turnstile` div in `index.html`, paste the site key.
3. `npx wrangler secret put TURNSTILE_SECRET` with the secret key.
The server checks the token only when `TURNSTILE_SECRET` is set. Tokens are valid for 300 seconds and only once, so a visitor who waits too long before submitting gets an error and must retry.
