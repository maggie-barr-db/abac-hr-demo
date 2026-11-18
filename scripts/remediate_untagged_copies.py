#!/usr/bin/env python3
"""Find untagged copies of sensitive columns in a schema (default: byod) and tag them from their sources.

Usage:
  python3 scripts/remediate_untagged_copies.py <profile> <warehouse_id> <catalog> [--schema byod] [--apply]

For every column in the target schema that has no sensitivity tier tag:
  1. Lineage: walk system.access.column_lineage upstream (through views) until it reaches
     tagged columns, and take the highest tier found. Catches renamed and derived columns
     (for example total_comp = base + bonus + equity). Lineage can lag by minutes.
  2. Name match (fallback): a tagged bronze/silver column with the same name.
It also carries the scope tag (e.g. reporting_line) across when the source column has it, so the
row filter applies to the copy too.

Without --apply it prints the plan. With --apply it runs the ALTER TABLE ... SET TAGS
statements; the existing catalog-level policies then protect the copy immediately.
In production this runs as a scheduled job under a governance service principal.
"""
import json
import subprocess
import sys
import time

TIER_ORDER = ["internal", "confidential", "restricted", "highly_restricted"]
TIER_TAG = "hr_pii_demo_tag"
SCOPE_TAG = "hr_scope_demo_tag"


def api(profile, method, endpoint, body=None):
    cmd = ["databricks", "api", method, endpoint, "-p", profile]
    if body is not None:
        cmd += ["--json", json.dumps(body)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode:
        raise RuntimeError(proc.stderr.strip()[:400])
    return json.loads(proc.stdout or "{}")


def sql(profile, warehouse, statement):
    resp = api(profile, "post", "/api/2.0/sql/statements",
               {"warehouse_id": warehouse, "statement": statement, "wait_timeout": "30s"})
    sid, state = resp.get("statement_id"), resp.get("status", {}).get("state")
    while state in ("PENDING", "RUNNING"):
        time.sleep(2)
        resp = api(profile, "get", f"/api/2.0/sql/statements/{sid}")
        state = resp.get("status", {}).get("state")
    if state != "SUCCEEDED":
        raise RuntimeError(f"{state}: {resp.get('status', {}).get('error', {}).get('message', '')[:300]}")
    return (resp.get("result") or {}).get("data_array") or []


def main():
    args = sys.argv[1:]
    if len(args) < 3:
        sys.exit(__doc__)
    profile, warehouse, catalog = args[:3]
    schema = args[args.index("--schema") + 1] if "--schema" in args else "byod"
    apply = "--apply" in args

    # All tags in the catalog: (schema.table.column) -> {tag_name: tag_value}
    tags = {}
    for s, t, c, k, v in sql(profile, warehouse,
                             f"SELECT schema_name, table_name, column_name, tag_name, tag_value "
                             f"FROM {catalog}.information_schema.column_tags "
                             f"WHERE tag_name IN ('{TIER_TAG}', '{SCOPE_TAG}')"):
        tags.setdefault(f"{catalog}.{s}.{t}.{c}", {})[k] = v

    # Untagged columns in the target schema
    untagged = [(t, c) for t, c in sql(profile, warehouse,
                f"SELECT table_name, column_name FROM {catalog}.information_schema.columns "
                f"WHERE table_schema = '{schema}' ORDER BY table_name, ordinal_position")
                if TIER_TAG not in tags.get(f"{catalog}.{schema}.{t}.{c}", {})]
    if not untagged:
        print(f"No untagged columns in {catalog}.{schema}.")
        return

    # Column lineage for the catalog (one pull, walked in memory)
    lineage = {}
    for tgt_t, tgt_c, src_t, src_c in sql(profile, warehouse,
            f"SELECT DISTINCT target_table_full_name, target_column_name, source_table_full_name, source_column_name "
            f"FROM system.access.column_lineage "
            f"WHERE target_table_full_name LIKE '{catalog}.%' AND source_table_full_name LIKE '{catalog}.%' "
            f"AND source_column_name IS NOT NULL AND target_column_name IS NOT NULL"):
        lineage.setdefault(f"{tgt_t}.{tgt_c}", set()).add(f"{src_t}.{src_c}")

    def upstream_tags(col, depth=0, seen=None):
        """Tags found by walking lineage upstream until tagged columns are reached."""
        seen = seen or set()
        found = []
        for src in lineage.get(col, ()):
            if src in seen:
                continue
            seen.add(src)
            if TIER_TAG in tags.get(src, {}):
                found.append(tags[src])
            elif depth < 5:
                found += upstream_tags(src, depth + 1, seen)
        return found

    by_name = {}
    for key, kv in tags.items():
        s = key.split(".")[1]
        if TIER_TAG in kv and (s.endswith("_silver") or s.endswith("_bronze")):
            name = key.rsplit(".", 1)[1]
            by_name.setdefault(name, []).append(kv)

    plan = []
    for t, c in untagged:
        col = f"{catalog}.{schema}.{t}.{c}"
        found, how = upstream_tags(col), "lineage"
        if not found:
            found, how = by_name.get(c, []), "name match"
        if not found:
            plan.append((t, c, None, None, "no source found: review manually"))
            continue
        tier = max((f[TIER_TAG] for f in found), key=TIER_ORDER.index)
        scope = next((f[SCOPE_TAG] for f in found if f.get(SCOPE_TAG)), None)
        plan.append((t, c, tier, scope, how))

    print(f"{'table':28} {'column':16} {'tier':18} {'scope':11} found by")
    for t, c, tier, scope, how in plan:
        print(f"{t:28} {c:16} {tier or '-':18} {scope or '-':11} {how}")

    if not apply:
        print("\nDry run. Re-run with --apply to tag these columns.")
        return
    for t, c, tier, scope, _ in plan:
        if not tier:
            continue
        sql(profile, warehouse, f"ALTER TABLE {catalog}.{schema}.{t} ALTER COLUMN {c} SET TAGS ('{TIER_TAG}' = '{tier}')")
        if scope:
            sql(profile, warehouse, f"ALTER TABLE {catalog}.{schema}.{t} ALTER COLUMN {c} SET TAGS ('{SCOPE_TAG}' = '{scope}')")
    print(f"\nTagged {sum(1 for p in plan if p[2])} columns. The catalog-level policies now apply to them.")


if __name__ == "__main__":
    main()
