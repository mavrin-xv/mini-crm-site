#!/usr/bin/env python3
"""Consistency check for a mini-crm-site app folder. Run it after every customisation.

The template keeps the same list in several places on purpose (code, database, form).
When they drift, things fail quietly: a status the database refuses, a service the
form offers but the server rejects, a "won" status the report never counts.

Checks:
  - STATUSES keys in src/config.js == CHECK (status IN ...) in the newest migration that sets it
  - OPEN_STATUSES and WON_STATUSES only use keys from STATUSES
  - SERVICES keys in src/config.js == <select name="service"> option values in public/index.html
  - every migration file is named NNNN_name.sql with no gaps or duplicate numbers
  - wrangler.toml (if present) has a real database_id and no secrets in [vars]
  - .gitignore (repo root or app) lists wrangler.toml and .dev.vars

Usage:
  python check_config.py path/to/app        (default: ./app)
Exit 0 = consistent, 1 = at least one error. Warnings do not fail. Stdlib only.
"""
import pathlib
import re
import sys


def keys_of(js, const):
    m = re.search(r"export const %s\s*=\s*\{(.*?)\};" % const, js, re.S)
    if not m:
        return None
    return re.findall(r"^\s*([a-z0-9_]+)\s*:", m.group(1), re.M)


def list_of(js, const):
    m = re.search(r"export const %s\s*=\s*\[(.*?)\];" % const, js, re.S)
    return re.findall(r"'([^']+)'|\"([^\"]+)\"", m.group(1)) if m else None


def main():
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    app = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "app")
    errors, warns = [], []
    cfg_path = app / "src" / "config.js"
    if not cfg_path.exists():
        print(f"no {cfg_path}: pass the app folder (the one with src/, public/, migrations/)")
        return 1
    cfg = cfg_path.read_text(encoding="utf-8")

    statuses = keys_of(cfg, "STATUSES") or []
    services = keys_of(cfg, "SERVICES") or []
    if not statuses:
        errors.append("STATUSES not found in config.js")
    for name in ("OPEN_STATUSES", "WON_STATUSES"):
        vals = list_of(cfg, name)
        if vals is None:
            warns.append(f"{name} not found in config.js")
            continue
        for a, b in vals:
            v = a or b
            if v not in statuses:
                errors.append(f"{name} uses '{v}', which is not a key in STATUSES")

    # migrations
    migs = sorted((app / "migrations").glob("*.sql"))
    nums = []
    for m in migs:
        mm = re.match(r"^(\d{4})_[a-z0-9_]+\.sql$", m.name)
        if not mm:
            errors.append(f"migration name {m.name} should look like 0003_add_field.sql")
        else:
            nums.append(int(mm.group(1)))
    if nums and sorted(nums) != list(range(1, len(nums) + 1)):
        errors.append(f"migration numbers have gaps or duplicates: {sorted(nums)}")
    check = None
    for m in migs:
        for found in re.findall(r"CHECK\s*\(\s*status\s+IN\s*\(([^)]*)\)", m.read_text(encoding="utf-8"), re.I):
            check = (m.name, re.findall(r"'([^']+)'", found))
    if not check:
        errors.append("no CHECK (status IN (...)) found in migrations")
    elif set(check[1]) != set(statuses):
        errors.append(f"STATUSES {sorted(statuses)} != database CHECK in {check[0]} {sorted(check[1])}. "
                      "Changing it needs a table rebuild migration, see references/schema-changes.md")

    # form
    page = app / "public" / "index.html"
    if page.exists():
        html = page.read_text(encoding="utf-8")
        sel = re.search(r'<select[^>]*name="service"[^>]*>(.*?)</select>', html, re.S)
        if not sel:
            warns.append("public/index.html has no <select name=\"service\">")
        else:
            opts = [v for v in re.findall(r'<option[^>]*value="([^"]*)"', sel.group(1)) if v]
            if set(opts) != set(services):
                errors.append(f"form service options {sorted(opts)} != SERVICES {sorted(services)}")
    else:
        warns.append("no public/index.html (fine if your site lives elsewhere and posts to /api/lead)")

    # wrangler.toml
    toml = app / "wrangler.toml"
    if toml.exists():
        t = toml.read_text(encoding="utf-8")
        if "REPLACE_WITH_ID" in t:
            errors.append("wrangler.toml still has the placeholder database_id (run `npx wrangler d1 create crm`)")
        vars_block = re.search(r"\[vars\](.*?)(\n\[|\Z)", t, re.S)
        if vars_block and re.search(r"(PASSWORD|SECRET|TOKEN)\s*=", vars_block.group(1)):
            errors.append("a secret is set in [vars] of wrangler.toml; use `npx wrangler secret put NAME` instead")
    else:
        warns.append("no wrangler.toml yet (copy wrangler.toml.example)")

    ignores = ""
    for gi in (app / ".gitignore", app.parent / ".gitignore"):
        if gi.exists():
            ignores += gi.read_text(encoding="utf-8")
    for must in ("wrangler.toml", ".dev.vars"):
        if must not in ignores:
            warns.append(f".gitignore does not list {must}")

    for w in warns:
        print("WARN ", w)
    for e in errors:
        print("ERROR", e)
    print(f"{'OK' if not errors else 'FAILED'}: {len(statuses)} statuses, {len(services)} services, "
          f"{len(migs)} migrations, {len(errors)} errors, {len(warns)} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
