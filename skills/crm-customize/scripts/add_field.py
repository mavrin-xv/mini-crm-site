#!/usr/bin/env python3
"""Add a custom field to leads (or contacts) the safe way: a new numbered migration
plus a checklist of every place that has to know about the field.

Usage:
  python add_field.py --app app --name square_feet --type integer --label "Square feet"
  python add_field.py --app app --name pet_friendly --type bool --label "Pets at home"
  python add_field.py --app app --name gate_code --type text --table contacts --label "Gate code"
  python add_field.py --app app --name square_feet --type integer --dry-run

Types: text, integer, bool (stored as INTEGER 0/1), date (TEXT YYYY-MM-DD).
What it does:
  1. Writes migrations/NNNN_add_<name>.sql with ALTER TABLE ... ADD COLUMN (nullable,
     so existing rows stay valid and the migration never fails on old data).
  2. Prints the touchpoints with file:line anchors: form input, server validation,
     INSERT, board card / detail view, report. It does not edit code for you: the field
     needs a human decision about validation and where it shows.
Never edits an applied migration. Stdlib only.
"""
import argparse
import pathlib
import re
import sys

SQL_TYPE = {"text": "TEXT", "integer": "INTEGER", "bool": "INTEGER", "date": "TEXT"}
VALIDATION = {
    "text": "clean(body.{n}, 200) || null",
    "integer": "body.{n} === '' || body.{n} == null ? null : +body.{n}\n"
               "     and before the return: if (body.{n} && !(Number.isInteger(+body.{n}) && +body.{n} >= 0))\n"
               "       return {{ ok: false, error: '{label} must be a whole number', field: '{n}' }};",
    "bool": "body.{n} === true || body.{n} === 'on' || body.{n} === '1' ? 1 : 0",
    "date": "ISO_DATE.test(clean(body.{n}, 10)) ? clean(body.{n}, 10) : null",
}
INPUT = {
    "text": '<label>{label}<input name="{n}" maxlength="200"></label>',
    "integer": '<label>{label}<input name="{n}" type="number" min="0" step="1"></label>',
    "bool": '<label><input name="{n}" type="checkbox" value="1"> {label}</label>',
    "date": '<label>{label}<input name="{n}" type="date"></label>',
}


def anchor(path, pattern):
    if not path.exists():
        return f"{path} (missing)"
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if re.search(pattern, line):
            return f"{path.as_posix()}:{i}"
    return f"{path.as_posix()} (anchor '{pattern}' not found)"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--app", default="app")
    ap.add_argument("--name", required=True, help="snake_case column name")
    ap.add_argument("--type", required=True, choices=SQL_TYPE)
    ap.add_argument("--label", help="label shown to people (default: from name)")
    ap.add_argument("--table", default="leads", choices=["leads", "contacts"])
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if not re.fullmatch(r"[a-z][a-z0-9_]{1,40}", a.name):
        sys.exit("name must be snake_case, 2..41 chars, start with a letter")
    app = pathlib.Path(a.app)
    mig_dir = app / "migrations"
    if not mig_dir.is_dir():
        sys.exit(f"no {mig_dir}")
    existing = "\n".join(p.read_text(encoding="utf-8") for p in sorted(mig_dir.glob("*.sql")))
    if re.search(r"\b%s\b" % re.escape(a.name), existing):
        sys.exit(f"'{a.name}' already appears in a migration; pick another name or check it is not there already")
    nums = [int(m.group(1)) for p in mig_dir.glob("*.sql") if (m := re.match(r"(\d{4})_", p.name))]
    nxt = (max(nums) if nums else 0) + 1
    fname = mig_dir / f"{nxt:04d}_add_{a.name}.sql"
    label = a.label or a.name.replace("_", " ").capitalize()
    sql = (f"-- Adds {a.table}.{a.name} ({label}). Nullable on purpose: old rows stay valid.\n"
           f"-- Apply: npx wrangler d1 migrations apply crm --local, test, then --remote\n"
           f"ALTER TABLE {a.table} ADD COLUMN {a.name} {SQL_TYPE[a.type]}"
           + (" CHECK ({0} IN (0,1))".format(a.name) if a.type == "bool" else "") + ";\n")
    if a.dry_run:
        print(f"[dry-run] would write {fname}:\n{sql}")
    else:
        fname.write_text(sql, encoding="utf-8", newline="\n")
        print(f"wrote {fname}")

    src = app / "src"
    print("\nTouchpoints (edit each, then run check_config.py and the tests):")
    steps = [
        ("form field", anchor(app / "public" / "index.html", r'name="message"'),
         INPUT[a.type].format(n=a.name, label=label)),
        ("server validation, inside validateLead() return", anchor(src / "lib.js", r"utm_campaign: clean"),
         f"{a.name}: " + VALIDATION[a.type].format(n=a.name, label=label)),
    ]
    if a.table == "leads":
        steps.append(("INSERT INTO leads column list + bind()", anchor(src / "worker.js", r"INSERT INTO leads \("),
                      f"add {a.name} to the column list, one more ?, and lead.{a.name} in .bind()"))
    else:
        steps.append(("contact upsert", anchor(src / "worker.js", r"INSERT INTO contacts"),
                      f"add {a.name} to INSERT and to ON CONFLICT ... SET {a.name} = COALESCE(excluded.{a.name}, contacts.{a.name})"))
    steps += [
        ("board detail view", anchor(src / "admin.js", r"d-msg"),
         f"show CUR.{a.name} with textContent (never innerHTML)"),
        ("Telegram message (optional)", anchor(src / "lib.js", r"if \(lead.area\)"),
         f"if (lead.{a.name} != null) lines.push(`{label}: ${{e(lead.{a.name})}}`);"),
        ("test", anchor(app / "test" / "run.mjs", r"const lead = \{"), f"add {a.name} to the test lead and assert it is stored"),
    ]
    for i, (what, where, hint) in enumerate(steps, 1):
        print(f"  {i}. {what}\n     at {where}\n     {hint}")
    print("\nThen: node --no-warnings test/run.mjs && python check_config.py "
          f"{app.as_posix()} && npx wrangler d1 migrations apply crm --remote && npx wrangler deploy")


if __name__ == "__main__":
    main()
