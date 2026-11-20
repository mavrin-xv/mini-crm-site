# Contributing

Thanks for helping. Small, tested changes are the easiest to merge.

## Good first contributions

- A `users` table with named operators, keeping the single-password mode as the default.
- An email or SMS notifier behind the same `notify()` call, keys through secrets only.
- New audit rules in `audit_worker.py` for mistakes you have seen in real lead Workers, each with a line in `examples/bad-worker.js` that triggers it.
- A second worked example config (a plumber, a tutoring school), with `check_config.py` passing.
- A calendar view for the bookings add-on.

## How

1. Open an issue first for anything that changes the schema or the public API.
2. Keep the app dependency-free at runtime and the scripts stdlib-only.
3. Run the commands listed in `AGENTS.md`. Paste their output in the PR.
4. Plain English. No hype words, no invented numbers. If a number is in the docs, say where it came from.

## Credit

If your change is based on someone else's method or repo, add it to the Credits section of the README with the URL and license.
