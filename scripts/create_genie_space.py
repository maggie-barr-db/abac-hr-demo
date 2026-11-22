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
# Answer-style instruction: keeps Genie from describing filtered results as company-wide,
# stops it from turning masked NULLs into 0, and ends every answer with an access note.
INSTRUCTIONS = [
    "Answers only include data the person asking is authorized to see. Unity Catalog applies row filters and column masks before any data reaches you.\n",
    "- Never describe results as company-wide or 'at the company'. Say 'among the employees you can see' (for a people manager: 'within your reporting line').\n",
    "- End every answer, with no exceptions, with this exact sentence on its own line: 'This answer reflects your access level; data you're not authorized to see has been omitted or masked.'\n",
    "- Never treat masked NULL values as 0, and don't use COALESCE to replace them. If a measure is NULL, say the value isn't available at your access level.",
]
space = {
    "version": 2,
    "data_sources": {"tables": [{"identifier": t} for t in sorted(tables)]},
    "instructions": {"text_instructions": [{"id": "0" * 32, "content": INSTRUCTIONS}]},
}
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
