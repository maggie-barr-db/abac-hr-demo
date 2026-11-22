#!/usr/bin/env python3
"""Ask a Genie space one question via the Conversation API and print the generated SQL, result and text.

Usage: python3 scripts/genie_ask.py <profile> <space_id> "<question>"
Runs as the CLI profile identity, so ABAC applies to that identity (and the demo persona override).
"""
import json, subprocess, sys, time
P, SPACE, Q = sys.argv[1], sys.argv[2], sys.argv[3]
def api(m, ep, body=None):
    cmd=["databricks","api",m,ep,"-p",P]+(["--json",json.dumps(body)] if body is not None else [])
    r=subprocess.run(cmd,capture_output=True,text=True)
    if r.returncode: raise SystemExit(r.stderr[:400])
    return json.loads(r.stdout or "{}")
r=api("post",f"/api/2.0/genie/spaces/{SPACE}/start-conversation",{"content":Q})
cid, mid = r["conversation_id"], r["message_id"]
for _ in range(60):
    m=api("get",f"/api/2.0/genie/spaces/{SPACE}/conversations/{cid}/messages/{mid}")
    if m.get("status") in ("COMPLETED","FAILED","CANCELLED"): break
    time.sleep(3)
print("status:",m.get("status"))
for a in m.get("attachments",[]) or []:
    if a.get("text"): print("text:",a["text"].get("content",""))
    if a.get("query"):
        print("sql:"," ".join(a["query"].get("query","").split())[:400])
        res=api("get",f"/api/2.0/genie/spaces/{SPACE}/conversations/{cid}/messages/{mid}/attachments/{a['attachment_id']}/query-result")
        sr=res.get("statement_response",{})
        cols=[c["name"] for c in sr.get("manifest",{}).get("schema",{}).get("columns",[])]
        rows=(sr.get("result",{}) or {}).get("data_array",[]) or []
        print("result:",cols,rows[:5])
