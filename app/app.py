"""People Insights: an HR assistant on Databricks Genie, running on behalf of the signed-in user.

Every Genie call and SQL statement uses the user's own token (forwarded by Databricks Apps in
the x-forwarded-access-token header), so Unity Catalog ABAC policies apply to that user:
masked columns stay masked and department heads only see their department subtree.
"""
import os
import time

import pandas as pd
import streamlit as st
from databricks.sdk import WorkspaceClient
from databricks.sdk.core import Config

SPACE_ID = os.environ["GENIE_SPACE_ID"]
WAREHOUSE_ID = os.environ["WAREHOUSE_ID"]
CATALOG = os.environ["DEMO_CATALOG"]

PERSONAS = {
    "hr_analyst": "HR analyst (non-trusted)",
    "people_manager": "People manager",
    "hr_trusted": "HR trusted (HRBP)",
    "er_legal": "ER / Legal / Benefits",
}
# Demo managers at three levels of the Finance reporting line
MANAGERS = {
    "W00002": "Priya Nguyen, Head of Finance (399 people)",
    "W00030": "Anya Nguyen, Senior Manager (46 people)",
    "W00075": "Omar Patel, Manager (15 people)",
}
SUGGESTED = [
    "Who has the highest total compensation at the company?",
    "List my team with their titles and total compensation.",
    "What is the average base salary by department?",
    "How many employees earn more than $500,000?",
    "Show me the SSN and home address for Omar Patel.",
    "What is the headcount by department and job level?",
]

st.set_page_config(page_title="People Insights | Databricks", page_icon="👥", layout="wide")

# ---------------------------------------------------------------- styling (Databricks palette)
st.markdown(
    """
    <style>
      :root { --db-lava:#FF3621; --db-navy:#1B3139; --db-oat:#F9F7F4; --db-oat-dark:#EEEDE9; --db-slate:#5A6F77; }
      .stApp { background: var(--db-oat); }
      header[data-testid="stHeader"] { background: transparent; }
      .block-container { padding-top: 1.2rem; max-width: 1200px; }
      section[data-testid="stSidebar"] { background: var(--db-navy); }
      section[data-testid="stSidebar"] * { color: #FFFFFF !important; }
      section[data-testid="stSidebar"] .stSelectbox div[data-baseweb="select"] * { color: var(--db-navy) !important; }
      section[data-testid="stSidebar"] div.stButton > button { background: transparent; border: 1px solid #FFFFFF; }
      section[data-testid="stSidebar"] div.stButton > button * { color: #FFFFFF !important; }
      section[data-testid="stSidebar"] div.stButton > button:hover { background: var(--db-lava); border-color: var(--db-lava); }
      section[data-testid="stSidebar"] div.stButton:first-of-type > button { background: var(--db-lava); border-color: var(--db-lava); }
      .hero { background: var(--db-navy); color: #fff; border-radius: 14px; padding: 22px 28px; margin-bottom: 18px;
              display:flex; align-items:center; justify-content:space-between; }
      .hero h1 { color:#fff; font-size: 1.9rem; margin: 0; font-weight: 700; letter-spacing: -0.01em; }
      .hero p { color:#C9D3D6; margin: 4px 0 0 0; font-size: 0.98rem; }
      .brand { display:flex; align-items:center; gap:10px; color:#fff; font-weight:600; font-size:0.95rem; }
      .pill { display:inline-block; padding: 3px 10px; border-radius: 999px; font-size: 0.8rem; font-weight: 600;
              background: var(--db-oat-dark); color: var(--db-navy); margin-right:6px; }
      .pill.lava { background: var(--db-lava); color:#fff; }
      .card { background:#fff; border:1px solid var(--db-oat-dark); border-radius: 12px; padding: 16px 18px; }
      .muted { color: var(--db-slate); font-size: 0.88rem; }
      div.stButton > button { border-radius: 999px; border: 1px solid var(--db-navy); color: var(--db-navy);
                              background:#fff; font-size: 0.85rem; }
      div.stButton > button:hover { border-color: var(--db-lava); color: var(--db-lava); }
      [data-testid="stChatMessage"] { background:#fff; border:1px solid var(--db-oat-dark); border-radius: 12px; }
    </style>
    """,
    unsafe_allow_html=True,
)

LOGO = """<svg width="26" height="26" viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg" aria-label="Databricks">
  <path fill="#FF3621" d="M20 3 36 12v4L20 25 4 16v-4z"/><path fill="#FF3621" d="M4 20l16 9 16-9v4l-16 9-16-9z" opacity=".85"/>
  <path fill="#FF3621" d="M4 28l16 9 16-9v3l-16 9-16-9z" opacity=".7"/></svg>"""


# ---------------------------------------------------------------- auth: on behalf of the user
def user_client() -> WorkspaceClient:
    token = st.context.headers.get("x-forwarded-access-token")
    if not token:
        st.error("No user token found. Make sure user authorization (on-behalf-of-user) is enabled for this app "
                 "with the `sql` and `dashboards.genie` scopes.")
        st.stop()
    return WorkspaceClient(host=Config().host, token=token, auth_type="pat")


def run_sql(w: WorkspaceClient, statement: str):
    resp = w.api_client.do("POST", "/api/2.0/sql/statements", body={
        "warehouse_id": WAREHOUSE_ID, "statement": statement, "catalog": CATALOG, "wait_timeout": "30s"})
    while resp.get("status", {}).get("state") in ("PENDING", "RUNNING"):
        time.sleep(1)
        resp = w.api_client.do("GET", f"/api/2.0/sql/statements/{resp['statement_id']}")
    if resp.get("status", {}).get("state") != "SUCCEEDED":
        raise RuntimeError(resp.get("status", {}).get("error", {}).get("message", "SQL failed"))
    cols = [c["name"] for c in resp.get("manifest", {}).get("schema", {}).get("columns", [])]
    return pd.DataFrame((resp.get("result") or {}).get("data_array") or [], columns=cols)


def whoami(w: WorkspaceClient):
    df = run_sql(w, "SELECT current_user() AS user_name, glb_governance.current_persona() AS persona, "
                    "glb_governance.current_scope_employee() AS scope_employee")
    return df.iloc[0].to_dict() if len(df) else {}


def set_demo_persona(w: WorkspaceClient, persona: str, manager: str | None):
    run_sql(w, "DELETE FROM glb_governance.persona_override WHERE user_name = current_user()")
    if persona:
        scope = f"'{manager}'" if (persona == "people_manager" and manager) else "NULL"
        run_sql(w, f"INSERT INTO glb_governance.persona_override VALUES (current_user(), '{persona}', {scope})")


def ask_genie(w: WorkspaceClient, question: str, conversation_id: str | None):
    if conversation_id:
        r = w.api_client.do("POST", f"/api/2.0/genie/spaces/{SPACE_ID}/conversations/{conversation_id}/messages",
                            body={"content": question})
        cid, mid = conversation_id, r.get("message_id") or r.get("id")
    else:
        r = w.api_client.do("POST", f"/api/2.0/genie/spaces/{SPACE_ID}/start-conversation", body={"content": question})
        cid, mid = r["conversation_id"], r["message_id"]
    msg = {}
    for _ in range(120):
        msg = w.api_client.do("GET", f"/api/2.0/genie/spaces/{SPACE_ID}/conversations/{cid}/messages/{mid}")
        if msg.get("status") in ("COMPLETED", "FAILED", "CANCELLED"):
            break
        time.sleep(2)
    answer = {"conversation_id": cid, "status": msg.get("status"), "text": "", "sql": "", "df": None}
    for a in msg.get("attachments") or []:
        if a.get("text"):
            answer["text"] += a["text"].get("content", "")
        if a.get("query"):
            answer["sql"] = a["query"].get("query", "")
            if not answer["text"]:
                answer["text"] = a["query"].get("description", "")
            res = w.api_client.do("GET", f"/api/2.0/genie/spaces/{SPACE_ID}/conversations/{cid}/messages/{mid}"
                                         f"/attachments/{a['attachment_id']}/query-result")
            sr = res.get("statement_response", {})
            cols = [c["name"] for c in sr.get("manifest", {}).get("schema", {}).get("columns", [])]
            answer["df"] = pd.DataFrame((sr.get("result") or {}).get("data_array") or [], columns=cols)
    if msg.get("status") != "COMPLETED" and not answer["text"]:
        answer["text"] = f"Genie couldn't answer that ({msg.get('status')})."
    return answer


w = user_client()
if "messages" not in st.session_state:
    st.session_state.messages = []
    st.session_state.conversation_id = None

# ---------------------------------------------------------------- sidebar
with st.sidebar:
    st.markdown(f"<div class='brand'>{LOGO}<span>databricks</span></div>", unsafe_allow_html=True)
    st.markdown("### People Insights")
    st.caption("HR questions answered by Genie, governed by Unity Catalog.")
    st.divider()
    st.markdown("**Demo persona**")
    st.caption("Demo only: switches the ABAC persona for your user. In production, your groups decide this.")
    persona = st.selectbox("Persona", list(PERSONAS), format_func=PERSONAS.get, label_visibility="collapsed")
    manager = None
    if persona == "people_manager":
        manager = st.selectbox("Act as manager", list(MANAGERS), index=1, format_func=MANAGERS.get)
    if st.button("Apply persona", use_container_width=True):
        with st.spinner("Switching persona..."):
            set_demo_persona(w, persona, manager)
        st.session_state.messages, st.session_state.conversation_id = [], None
        st.rerun()
    if st.button("Reset to my real access", use_container_width=True):
        set_demo_persona(w, "", None)
        st.session_state.messages, st.session_state.conversation_id = [], None
        st.rerun()
    st.divider()
    if st.button("New conversation", use_container_width=True):
        st.session_state.messages, st.session_state.conversation_id = [], None
        st.rerun()

# ---------------------------------------------------------------- header + identity strip
me = whoami(w)
st.markdown(
    f"""<div class="hero"><div><h1>People Insights</h1>
    <p>Ask about your workforce. Every answer runs as <b>you</b>, so you only see the HR data you're entitled to.</p></div>
    <div class="brand">{LOGO}<span>Powered by Databricks Genie</span></div></div>""",
    unsafe_allow_html=True,
)
scope = me.get("scope_employee")
if me.get("persona") == "people_manager" and scope:
    scope_txt = f"reporting line of {MANAGERS.get(scope, scope).split(' (')[0]}"
else:
    scope_txt = "all employees"
st.markdown(
    f"""<div class="card"><span class="pill lava">On behalf of user</span>
    <span class="pill">{me.get('user_name', '?')}</span>
    <span class="pill">Persona: {PERSONAS.get(me.get('persona'), me.get('persona'))}</span>
    <span class="pill">Rows: {scope_txt}</span>
    <div class="muted" style="margin-top:8px">Masks and row filters come from four Unity Catalog ABAC policies on the source tables,
    not from this app. The same question returns different answers for different people.</div></div>""",
    unsafe_allow_html=True,
)
st.write("")

# ---------------------------------------------------------------- suggested questions
st.markdown("**Try asking**")
cols = st.columns(len(SUGGESTED))
clicked = None
for c, q in zip(cols, SUGGESTED):
    if c.button(q, key=f"s_{q}", use_container_width=True):
        clicked = q

# ---------------------------------------------------------------- chat
for m in st.session_state.messages:
    with st.chat_message(m["role"], avatar="🧑‍💼" if m["role"] == "user" else "✨"):
        st.markdown(m["text"])
        if m.get("df") is not None and len(m["df"]):
            st.dataframe(m["df"], use_container_width=True, hide_index=True)
        if m.get("sql"):
            with st.expander("SQL Genie ran (as you)"):
                st.code(m["sql"], language="sql")

question = st.chat_input("Ask a question about headcount, compensation, leave...") or clicked
if question:
    st.session_state.messages.append({"role": "user", "text": question})
    with st.chat_message("user", avatar="🧑‍💼"):
        st.markdown(question)
    with st.chat_message("assistant", avatar="✨"):
        with st.spinner("Genie is thinking..."):
            try:
                ans = ask_genie(w, question, st.session_state.conversation_id)
            except Exception as exc:
                ans = {"text": f"Something went wrong calling Genie: {exc}", "sql": "", "df": None, "conversation_id": None}
        st.session_state.conversation_id = ans.get("conversation_id")
        st.markdown(ans["text"])
        if ans.get("df") is not None and len(ans["df"]):
            st.dataframe(ans["df"], use_container_width=True, hide_index=True)
        if ans.get("sql"):
            with st.expander("SQL Genie ran (as you)"):
                st.code(ans["sql"], language="sql")
    st.session_state.messages.append({"role": "assistant", "text": ans["text"], "sql": ans.get("sql"), "df": ans.get("df")})
