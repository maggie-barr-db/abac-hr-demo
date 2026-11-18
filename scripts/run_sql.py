#!/usr/bin/env python3
"""Run a templated .sql file statement by statement against a Databricks SQL warehouse.

Uses the `databricks api` CLI, so it needs no extra Python packages and reuses CLI profile auth.

Usage:
  python3 scripts/run_sql.py <profile> <warehouse_id> <path.sql> [-v key=value ...]

Template variables in the SQL look like {{catalog}}. Defaults match databricks.yml and can be
overridden with -v. The script stops on the first failure and prints result rows for any
statement that returns data.
"""
import json
import subprocess
import sys
import time

DEFAULTS = {
    "catalog": "mbarrett_hr_demo_aws_sandbox_catalog",
    "tier_tag": "hr_pii_demo_tag",
    "scope_tag": "hr_scope_demo_tag",
}


def parse_args(argv):
    if len(argv) < 4:
        sys.exit(__doc__)
    profile, warehouse, path = argv[1], argv[2], argv[3]
    variables = dict(DEFAULTS)
    rest = argv[4:]
    i = 0
    while i < len(rest):
        if rest[i] == "-v" and i + 1 < len(rest):
            key, _, value = rest[i + 1].partition("=")
            variables[key] = value
            i += 2
        else:
            sys.exit(f"Unexpected argument: {rest[i]}")
    return profile, warehouse, path, variables


def render(text, variables):
    for key, value in variables.items():
        text = text.replace("{{" + key + "}}", value)
    if "{{" in text:
        missing = sorted({chunk.split("}}")[0] for chunk in text.split("{{")[1:]})
        sys.exit(f"Unrendered template variables: {missing}")
    return text


def split_statements(sql):
    """Split on semicolons outside quotes and $$ blocks; drop full-line comments."""
    sql = "\n".join(line for line in sql.splitlines() if not line.strip().startswith("--"))
    out, buf = [], []
    in_str, in_dollar = False, False
    i = 0
    while i < len(sql):
        if not in_str and sql.startswith("$$", i):
            in_dollar = not in_dollar
            buf.append("$$")
            i += 2
            continue
        ch = sql[i]
        if ch == "'" and not in_dollar:
            in_str = not in_str
        if ch == ";" and not in_str and not in_dollar:
            stmt = "".join(buf).strip()
            if stmt:
                out.append(stmt)
            buf = []
        else:
            buf.append(ch)
        i += 1
    tail = "".join(buf).strip()
    if tail:
        out.append(tail)
    return out


def api(profile, method, endpoint, payload=None):
    cmd = ["databricks", "api", method, endpoint, "--profile", profile]
    if payload is not None:
        cmd += ["--json", json.dumps(payload)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or proc.stdout.strip())
    return json.loads(proc.stdout) if proc.stdout.strip() else {}


def main():
    profile, warehouse, path, variables = parse_args(sys.argv)
    statements = split_statements(render(open(path).read(), variables))
    print(f"Executing {len(statements)} statements from {path} on warehouse {warehouse}\n")
    for n, stmt in enumerate(statements, 1):
        label = " ".join(stmt.split())[:80]
        resp = api(profile, "post", "/api/2.0/sql/statements",
                   {"warehouse_id": warehouse, "statement": stmt, "wait_timeout": "30s"})
        sid = resp.get("statement_id")
        state = resp.get("status", {}).get("state", "UNKNOWN")
        waited = 0
        while state in ("PENDING", "RUNNING") and waited < 600:
            time.sleep(3)
            waited += 3
            resp = api(profile, "get", f"/api/2.0/sql/statements/{sid}")
            state = resp.get("status", {}).get("state", "UNKNOWN")
        if state != "SUCCEEDED":
            err = resp.get("status", {}).get("error", {}).get("message", "")
            print(f"[{n}/{len(statements)}] FAILED: {label}\n    -> {state}: {err}")
            sys.exit(1)
        print(f"[{n}/{len(statements)}] ok  {label}")
        cols = [c["name"] for c in resp.get("manifest", {}).get("schema", {}).get("columns", [])]
        rows = resp.get("result", {}).get("data_array", []) or []
        if cols and rows:
            print("    " + " | ".join(cols))
            for row in rows[:50]:
                print("    " + " | ".join("NULL" if v is None else str(v) for v in row))
    print("\nDONE")


if __name__ == "__main__":
    main()
