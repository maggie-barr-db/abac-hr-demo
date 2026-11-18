#!/usr/bin/env python3
"""Create the demo Genie space over the gold views and metric view.

Usage: python3 scripts/create_genie_space.py <profile> <warehouse_id> <catalog>
Prints the new space_id. Uses the `databricks api` CLI and profile auth.
"""
import json
import subprocess
import sys

profile, warehouse, catalog = sys.argv[1], sys.argv[2], sys.argv[3]
tables = [
    f"{catalog}.glb_gold.employee_directory",
    f"{catalog}.glb_gold.workforce_summary",
    f"{catalog}.tr_gold.employee_comp",
    f"{catalog}.tr_gold.mv_total_comp",
]
space = {"version": 1, "data_sources": {"tables": [{"identifier": t} for t in tables]}}
body = {
    "warehouse_id": warehouse,
    "title": "HR People Analytics (ABAC demo)",
    "description": "Synthetic HR data. Answers follow each user's access: ABAC masks and row filters on the source tables apply to every query.",
    "serialized_space": json.dumps(space),
}
proc = subprocess.run(["databricks", "api", "post", "/api/2.0/genie/spaces", "-p", profile, "--json", json.dumps(body)],
                      capture_output=True, text=True)
if proc.returncode:
    sys.exit(proc.stderr)
print(json.loads(proc.stdout)["space_id"])
