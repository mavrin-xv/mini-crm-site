# QA checklist for a lead or booking Worker

Each item came from a real QA pass on a small booking site and CRM. Items marked (scan) are checked by `audit_worker.py`; the rest need a person or a test.

## Access
- [ ] (probe) Every GET under `/api/` except health returns 401 without a cookie. Try the obvious names: leads, bookings, contacts, customers, export, stats.
- [ ] Every PATCH / POST / DELETE that changes data returns 401 without a cookie and 403 with a foreign `Origin`.
- [ ] (scan H01) No `env.X || 'default'` for any password, token or secret.
- [ ] (scan H02) View source of `/admin`: no token, key or password in the HTML or inline JS.
- [ ] (scan H03) Password compared in constant time.
- [ ] (scan H07) Session cookie is HttpOnly, Secure, SameSite, signed, and expires.
- [ ] Logging out clears the cookie (`Max-Age=0`).
- [ ] Admin with secrets unset answers 503, not an open board.

## Input
- [ ] (scan H04) No SQL text built from request data.
- [ ] Phone, name, message have max lengths on the server.
- [ ] Dates: valid format, not in the past, end after start.
- [ ] Service and status accepted only from the config lists. An unknown status gives 400, not 500.
- [ ] (scan H12) Bad JSON gives 400.
- [ ] (scan H10) Errors return a fixed message; details go to `console.error`.

## Lead safety
- [ ] (scan H09) The row is saved before any notification is sent.
- [ ] A failing bot or webhook does not fail the request. Test: set a wrong chat id, submit, lead is saved and the event log says `notify_fail`.
- [ ] (scan H05) Alert text escapes every user value. Test: submit a name `<b>x` and see the alert arrive.
- [ ] Double submit (two taps) creates one lead.
- [ ] (scan H08) Honeypot, rate limit, optional Turnstile on the public POST.
- [ ] The form shows success only after the server says `ok:true`.

## Consistency
- [ ] (scan H11) One constant for statuses that hold a slot or count as won. Grep for every `IN ('` and every `['new'` style array; all must come from the constant.
- [ ] `check_config.py` passes: config, database CHECK and form agree.
- [ ] Statuses the server accepts are all shown as columns on the board. A lead in a status with no column is invisible.
- [ ] Timezone: cron alerts fire in local work hours, digest at local morning. Test with fixed dates as `test/run.mjs` does.

## Data
- [ ] Exports and backups are not in the repo and not in a public bucket.
- [ ] `wrangler.toml`, `.dev.vars` are git-ignored.
- [ ] IP addresses are stored hashed, and old `form_hits` rows are pruned.
- [ ] Test data (+1555 numbers) is marked spam or removed after the smoke test.
