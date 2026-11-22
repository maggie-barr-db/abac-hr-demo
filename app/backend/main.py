"""People Insights backend (FastAPI). Serves the React UI and the API it calls.

Every request runs as the signed-in user: Databricks Apps forwards the user's token in the
x-forwarded-access-token header (user authorization scopes: sql, dashboards.genie), and every SQL
statement and Genie call uses it. Unity Catalog ABAC policies therefore apply to the person using
the app: masked columns come back masked and people managers only get rows for their reporting line.

The app hides tabs a persona doesn't need, but that is presentation only. Access is enforced by
Unity Catalog, so calling an endpoint for a hidden tab returns masked or filtered data.
"""
import os
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from databricks.sdk import WorkspaceClient
from databricks.sdk.core import Config
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

SPACE_ID = os.environ["GENIE_SPACE_ID"]
WAREHOUSE_ID = os.environ["WAREHOUSE_ID"]
C = os.environ["DEMO_CATALOG"]
GOV = f"{C}.glb_governance"

PERSONAS = ["hr_analyst", "people_manager", "hr_trusted", "er_legal"]
MANAGERS = ["W00002", "W00030", "W00075"]
MASK = "****"

app = FastAPI(title="People Insights")
_host = Config().host


# ---------------------------------------------------------------- helpers
def user_client(req: Request) -> WorkspaceClient:
    token = req.headers.get("x-forwarded-access-token")
    if not token and os.getenv("LOCAL_DEV_PROFILE"):
        # Local development only: run as the CLI profile identity (never set in the deployed app)
        return WorkspaceClient(profile=os.environ["LOCAL_DEV_PROFILE"])
    if not token:
        raise HTTPException(401, "No user token. Enable user authorization (sql, dashboards.genie) for this app.")
    return WorkspaceClient(host=_host, token=token, auth_type="pat")


def sql(w: WorkspaceClient, statement: str, params: dict | None = None) -> list[dict]:
    body = {"warehouse_id": WAREHOUSE_ID, "statement": statement, "wait_timeout": "30s",
            "parameters": [{"name": k, "value": str(v)} for k, v in (params or {}).items()]}
    r = w.api_client.do("POST", "/api/2.0/sql/statements", body=body)
    while r.get("status", {}).get("state") in ("PENDING", "RUNNING"):
        time.sleep(0.5)
        r = w.api_client.do("GET", f"/api/2.0/sql/statements/{r['statement_id']}")
    if r.get("status", {}).get("state") != "SUCCEEDED":
        raise HTTPException(502, r.get("status", {}).get("error", {}).get("message", "SQL failed"))
    cols = [c["name"] for c in r.get("manifest", {}).get("schema", {}).get("columns", [])]
    return [dict(zip(cols, row)) for row in (r.get("result") or {}).get("data_array") or []]


_pool = ThreadPoolExecutor(max_workers=16)


def sql_many(w: WorkspaceClient, *statements, params: dict | None = None) -> list[list[dict]]:
    """Run independent statements in parallel (each page needs several)."""
    return list(_pool.map(lambda st: sql(w, st, params), statements))


def visible(v) -> bool:
    """True when a value came back in clear (not masked to '****' or NULL)."""
    return v is not None and v != MASK


# ---------------------------------------------------------------- identity
@app.get("/api/me")
def me(req: Request):
    w = user_client(req)
    r = sql(w, f"""
        SELECT current_user() AS user_name, {GOV}.current_persona() AS persona,
               {GOV}.current_scope_employee() AS scope_employee,
               (SELECT full_name FROM {C}.glb_silver.employees WHERE employee_id = {GOV}.current_scope_employee()) AS scope_name,
               (SELECT job_title FROM {C}.glb_silver.employees WHERE employee_id = {GOV}.current_scope_employee()) AS scope_title,
               (SELECT count(*) FROM {C}.glb_silver.employees) AS visible_employees,
               EXISTS (SELECT 1 FROM {GOV}.persona_override WHERE user_name = current_user()) AS demo_override""")[0]
    persona = r["persona"]
    tabs = ["overview", "directory"]
    if persona == "people_manager":
        tabs.append("team")
    if persona in ("hr_trusted", "er_legal"):
        tabs.append("comp")
    tabs += ["ask", "access"]
    return {**r, "demo_override": r["demo_override"] == "true", "visible_employees": int(r["visible_employees"]), "tabs": tabs}


class PersonaIn(BaseModel):
    persona: str | None = None
    manager: str | None = None


@app.post("/api/persona")
def set_persona(body: PersonaIn, req: Request):
    """DEMO ONLY: switch the ABAC persona for the signed-in user through the override table."""
    w = user_client(req)
    sql(w, f"DELETE FROM {GOV}.persona_override WHERE user_name = current_user()")
    if body.persona:
        if body.persona not in PERSONAS:
            raise HTTPException(400, "unknown persona")
        scope = body.manager if body.persona == "people_manager" else None
        if scope and scope not in MANAGERS:
            raise HTTPException(400, "unknown manager")
        sql(w, f"INSERT INTO {GOV}.persona_override VALUES (current_user(), :p, " + (":s)" if scope else "NULL)"),
            {"p": body.persona, **({"s": scope} if scope else {})})
    return {"ok": True}


# ---------------------------------------------------------------- overview
@app.get("/api/overview")
def overview(req: Request):
    w = user_client(req)
    k, by_dept, by_level = sql_many(w, f"""
        SELECT
          (SELECT count(*) FROM {C}.glb_gold.employee_directory) AS headcount,
          (SELECT count(DISTINCT dept_id) FROM {C}.glb_gold.employee_directory) AS departments,
          (SELECT round(avg(datediff(current_date(), hire_date)) / 365.25, 1) FROM {C}.glb_gold.employee_directory) AS avg_tenure,
          (SELECT count(*) FROM {C}.ta_silver.requisitions WHERE status = 'Open') AS open_reqs,
          (SELECT sum(total_comp) FROM {C}.tr_gold.employee_comp) AS total_comp,
          (SELECT count_if(rating IN ('Exceeds', 'Exceptional')) / nullif(count(rating), 0)
             FROM {C}.glb_silver.performance WHERE review_year = 2026 AND rating <> '{MASK}') AS high_perf_share""", f"""
        SELECT dept_name, count(*) AS headcount
        FROM {C}.glb_gold.employee_directory GROUP BY dept_name ORDER BY headcount DESC, dept_name""", f"""
        SELECT job_level, count(*) AS headcount
        FROM {C}.glb_gold.employee_directory GROUP BY job_level
        ORDER BY int(substr(job_level, 2))""")
    return {"kpis": k[0], "by_dept": by_dept, "by_level": by_level}


# ---------------------------------------------------------------- directory + profile
@app.get("/api/directory")
def directory(req: Request, q: str = ""):
    w = user_client(req)
    return sql(w, f"""
        SELECT employee_id, full_name, job_title, job_level, dept_name, country, hire_date, work_email,
               home_address, personal_phone, date_of_birth, ssn
        FROM {C}.glb_gold.employee_directory
        WHERE :q = '' OR lower(full_name) LIKE concat('%', lower(:q), '%')
           OR lower(job_title) LIKE concat('%', lower(:q), '%') OR lower(dept_name) LIKE concat('%', lower(:q), '%')
           OR lower(employee_id) LIKE concat('%', lower(:q), '%')
        ORDER BY int(substr(job_level, 2)) DESC, full_name LIMIT 200""", {"q": q.strip()})


@app.get("/api/person/{emp}")
def person(emp: str, req: Request):
    w = user_client(req)
    p = {"e": emp}
    base, comp, perf, leave, training = sql_many(w, f"""
        SELECT d.*, m.full_name AS manager_name
        FROM {C}.glb_gold.employee_directory d
        LEFT JOIN {C}.glb_gold.employee_directory m ON m.employee_id = d.manager_id
        WHERE d.employee_id = :e""",
        f"SELECT base_salary, bonus_target, equity_grant, total_comp, currency FROM {C}.tr_gold.employee_comp WHERE employee_id = :e",
        f"SELECT review_year, rating, review_text, promotion_history FROM {C}.glb_silver.performance WHERE employee_id = :e ORDER BY review_year DESC LIMIT 1",
        f"SELECT leave_type, leave_balance_hours, medical_leave_reason FROM {C}.glb_silver.leave_records WHERE employee_id = :e LIMIT 3",
        f"SELECT course_name, completion_status, assessment_score FROM {C}.lrn_silver.training_records WHERE employee_id = :e LIMIT 5",
        params=p)
    if not base:
        raise HTTPException(404, "Not visible to you")
    return {"person": base[0], "comp": comp[0] if comp else None, "performance": perf[0] if perf else None,
            "leave": leave, "training": training}


# ---------------------------------------------------------------- my team (reporting line)
@app.get("/api/team")
def team(req: Request):
    w = user_client(req)
    people, reqs = sql_many(w, f"""
        SELECT d.employee_id, d.full_name, d.job_title, d.job_level, d.manager_id, d.dept_name,
               c.total_comp, p.rating
        FROM {C}.glb_gold.employee_directory d
        LEFT JOIN {C}.tr_gold.employee_comp c ON c.employee_id = d.employee_id
        LEFT JOIN {C}.glb_silver.performance p ON p.employee_id = d.employee_id AND p.review_year = 2026
        WHERE d.employee_id IN (SELECT report_id FROM {GOV}.reporting_closure
                                WHERE manager_id = {GOV}.current_scope_employee())
        ORDER BY int(substr(d.job_level, 2)) DESC, d.full_name""", f"""
        SELECT r.requisition_id, r.job_title, r.status, r.hiring_manager_id, m.full_name AS hiring_manager,
               (SELECT count(*) FROM {C}.ta_silver.applications a WHERE a.requisition_id = r.requisition_id) AS applicants
        FROM {C}.ta_silver.requisitions r
        LEFT JOIN {C}.glb_silver.employees m ON m.employee_id = r.hiring_manager_id
        ORDER BY r.status, r.requisition_id""")
    return {"people": people, "requisitions": reqs}


# ---------------------------------------------------------------- compensation (metric view)
@app.get("/api/comp")
def comp(req: Request):
    w = user_client(req)
    by_dept, by_level = sql_many(w, f"""
        SELECT department, MEASURE(headcount) AS headcount, round(MEASURE(avg_base_salary), 0) AS avg_base,
               round(MEASURE(avg_total_comp), 0) AS avg_total_comp, MEASURE(total_comp) AS total_comp
        FROM {C}.tr_gold.mv_total_comp GROUP BY department ORDER BY avg_total_comp DESC NULLS LAST, department""", f"""
        SELECT job_level, MEASURE(headcount) AS headcount, round(MEASURE(avg_base_salary), 0) AS avg_base,
               round(MEASURE(avg_total_comp), 0) AS avg_total_comp, MEASURE(max_total_comp) AS max_total_comp
        FROM {C}.tr_gold.mv_total_comp GROUP BY job_level ORDER BY int(substr(job_level, 2))""")
    return {"by_dept": by_dept, "by_level": by_level}


# ---------------------------------------------------------------- my access
TIERS = [
    ("internal", "Tier 1 - Internal", "Name, title, department, hire date",
     f"SELECT max(full_name) AS v FROM {C}.glb_silver.employees"),
    ("confidential", "Tier 2 - Confidential", "Performance rating, review text, training scores",
     f"SELECT max(rating) AS v FROM {C}.glb_silver.performance"),
    ("restricted", "Tier 3 - Restricted", "Compensation, home address, date of birth, personal phone",
     f"SELECT CAST(max(base_salary) AS STRING) AS v FROM {C}.tr_silver.compensation"),
    ("highly_restricted", "Tier 4 - Highly restricted", "SSN, bank details, medical leave reason, ER case notes",
     f"SELECT max(ssn) AS v FROM {C}.glb_silver.employees"),
]


@app.get("/api/access")
def access(req: Request):
    w = user_client(req)
    results = sql_many(w, *[t[3] for t in TIERS])
    return {"tiers": [{"tier": key, "label": label, "examples": ex, "clear": visible(r[0]["v"])}
                      for (key, label, ex, _), r in zip(TIERS, results)]}


# ---------------------------------------------------------------- ask (Genie Conversation API, as the user)
class AskIn(BaseModel):
    question: str
    conversation_id: str | None = None


@app.post("/api/ask")
def ask(body: AskIn, req: Request):
    w = user_client(req)
    base = f"/api/2.0/genie/spaces/{SPACE_ID}"
    if body.conversation_id:
        r = w.api_client.do("POST", f"{base}/conversations/{body.conversation_id}/messages", body={"content": body.question})
        cid, mid = body.conversation_id, r.get("message_id") or r.get("id")
    else:
        r = w.api_client.do("POST", f"{base}/start-conversation", body={"content": body.question})
        cid, mid = r["conversation_id"], r["message_id"]
    msg = {}
    for _ in range(90):
        msg = w.api_client.do("GET", f"{base}/conversations/{cid}/messages/{mid}")
        if msg.get("status") in ("COMPLETED", "FAILED", "CANCELLED"):
            break
        time.sleep(1.5)
    out = {"conversation_id": cid, "status": msg.get("status"), "text": "", "sql": "", "columns": [], "rows": []}
    for a in msg.get("attachments") or []:
        if a.get("text"):
            out["text"] += ("\n\n" if out["text"] else "") + a["text"].get("content", "")
        if a.get("query"):
            out["sql"] = a["query"].get("query", "")
            if not out["text"]:
                out["text"] = a["query"].get("description", "")
            res = w.api_client.do("GET", f"{base}/conversations/{cid}/messages/{mid}/attachments/{a['attachment_id']}/query-result")
            sr = res.get("statement_response", {})
            out["columns"] = [c["name"] for c in sr.get("manifest", {}).get("schema", {}).get("columns", [])]
            out["rows"] = ((sr.get("result") or {}).get("data_array") or [])[:50]
    if msg.get("status") != "COMPLETED" and not out["text"]:
        out["text"] = f"Genie couldn't answer that ({msg.get('status') or 'timed out'})."
    return out


# ---------------------------------------------------------------- static UI
DIST = Path(__file__).resolve().parent.parent / "frontend" / "dist"
if DIST.exists():
    app.mount("/assets", StaticFiles(directory=DIST / "assets"), name="assets")


@app.get("/{path:path}")
def spa(path: str):
    index = DIST / "index.html"
    if not index.exists():
        raise HTTPException(404, "UI not built. Run: cd app/frontend && npm install && npm run build")
    # never cache the page shell, so a redeploy is picked up on the next load
    return FileResponse(index, headers={"Cache-Control": "no-store"})
