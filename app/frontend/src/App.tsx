import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { api, type Row } from "./api";

// ------------------------------------------------------------------ constants
const PERSONAS: Record<string, { label: string; desc: string }> = {
  hr_analyst: { label: "HR analyst", desc: "Tier 1 only, all employees" },
  people_manager: { label: "People manager", desc: "Tiers 1-3, own reporting line only" },
  hr_trusted: { label: "HR trusted (HRBP)", desc: "Tiers 1-3, all employees" },
  er_legal: { label: "ER / Legal / Benefits", desc: "All four tiers, all employees" },
};
const TABS: Record<string, string> = {
  overview: "Overview", directory: "Directory", team: "My Team", comp: "Compensation", ask: "Ask AI", access: "My Access",
};
const SUGGESTED: Record<string, string[]> = {
  hr_analyst: [
    "What is the headcount by department and job level?",
    "Who has the highest total compensation at the company?",
    "What is the average base salary by department?",
    "Show me the SSN and home address for Omar Patel.",
  ],
  people_manager: [
    "List my team with their titles and total compensation.",
    "Who has the highest total compensation at the company?",
    "What is the total payroll for the whole company?",
    "Show me the SSN and home address for Omar Patel.",
  ],
  default: [
    "What is the average total compensation by department?",
    "How many employees earn more than $500,000?",
    "Who has the highest total compensation at the company?",
    "Show me the SSN and home address for Omar Patel.",
  ],
};
// The three demo managers (fixed list: the picker must work while you're acting as one of them,
// when the others may sit outside your own reporting line)
const MANAGERS = [
  { id: "W00002", name: "Priya Nguyen", title: "Head of Finance", line: 399 },
  { id: "W00030", name: "Anya Nguyen", title: "Senior Manager", line: 46 },
  { id: "W00075", name: "Omar Patel", title: "Manager", line: 15 },
];
const ACCESS_NOTE = "This answer reflects your access level";

// ------------------------------------------------------------------ icons
const Spark = () => (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M12 2l2.2 6.3L20.5 10l-6.3 2.2L12 18.5l-2.2-6.3L3.5 10l6.3-1.7z" /><path d="M19 15l.9 2.3 2.1.7-2.1.8L19 21l-.8-2.2L16 18l2.2-.7z" opacity=".75" /></svg>
);
const Lock = () => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" aria-hidden><rect x="5" y="11" width="14" height="10" rx="2" /><path d="M8 11V8a4 4 0 0 1 8 0v3" /></svg>
);
const Check = () => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" aria-hidden><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
);
const SearchIcon = () => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" aria-hidden><circle cx="11" cy="11" r="7" /><path d="M20 20l-3.5-3.5" /></svg>
);
const Shield = () => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" aria-hidden><path d="M12 3l8 3v6c0 4.5-3.4 8.3-8 9-4.6-.7-8-4.5-8-9V6z" /></svg>
);

// ------------------------------------------------------------------ helpers
const masked = (v: any) => v === null || v === undefined || v === "****";
const Restricted = ({ label = "Restricted" }: { label?: string }) => <span className="restricted"><Lock />{label}</span>;
const show = (v: any, f: (x: any) => ReactNode = (x) => x) => (masked(v) ? <Restricted /> : f(v));
const fmtInt = (v: any) => Number(v).toLocaleString("en-US");
const money = (v: any) => {
  const n = Number(v);
  if (Math.abs(n) >= 1e6) return `$${(n / 1e6).toFixed(n >= 1e7 ? 0 : 1)}M`;
  if (Math.abs(n) >= 1e3) return `$${Math.round(n / 1e3).toLocaleString("en-US")}K`;
  return `$${Math.round(n).toLocaleString("en-US")}`;
};
const cell = (v: any) => (/^-?\d+(\.\d+)?$/.test(String(v)) ? Number(v).toLocaleString("en-US", { maximumFractionDigits: 2 }) : String(v));
const moneyFull = (v: any) => `$${Math.round(Number(v)).toLocaleString("en-US")}`;
const COLORS = ["#1B3139", "#2f5260", "#FF5F46", "#7B61FF", "#00A972", "#E8A100", "#5A6F77", "#b3261e"];
const initials = (n: string) => (n || "?").split(" ").map((p) => p[0]).slice(0, 2).join("");
const color = (s: string) => COLORS[[...(s || "")].reduce((a, c) => a + c.charCodeAt(0), 0) % COLORS.length];
const Ini = ({ name }: { name: string }) => <div className="ini" style={{ background: color(name) }}>{initials(name)}</div>;
const ratingPill = (r: any) => {
  if (masked(r)) return <Restricted />;
  const cls = r === "Exceptional" ? "violet" : r === "Exceeds" ? "green" : r === "Meets" ? "navy" : "amber";
  return <span className={`pill ${cls}`}>{r}</span>;
};
const TierTag = ({ n }: { n: 1 | 2 | 3 | 4 }) => (
  <span className={`tier t${n}`}>{["", "Tier 1 internal", "Tier 2 confidential", "Tier 3 restricted", "Tier 4 highly restricted"][n]}</span>
);

function useLoad<T>(fn: () => Promise<T>, deps: unknown[]) {
  const [state, setState] = useState<{ data?: T; err?: string; loading: boolean }>({ loading: true });
  useEffect(() => {
    let live = true;
    setState((s) => ({ data: s.data, loading: true }));
    fn().then((data) => live && setState({ data, loading: false }))
      .catch((e) => live && setState({ err: String(e.message || e), loading: false }));
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return state;
}

function renderMd(text: string) {
  const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const inline = (s: string) => esc(s).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>").replace(/`([^`]+)`/g, "<code>$1</code>");
  const lines = text.split("\n");
  const body: string[] = [];
  let note = "";
  let list: string[] = [];
  const flush = () => { if (list.length) { body.push(`<ul>${list.map((l) => `<li>${l}</li>`).join("")}</ul>`); list = []; } };
  for (const raw of lines) {
    const l = raw.trim();
    if (!l) { flush(); continue; }
    if (l.includes(ACCESS_NOTE)) { note = inline(l); continue; }
    if (/^[-*•]\s+/.test(l)) { list.push(inline(l.replace(/^[-*•]\s+/, ""))); continue; }
    flush();
    body.push(`<p>${inline(l)}</p>`);
  }
  flush();
  return { body: body.join(""), note };
}

// ------------------------------------------------------------------ app
type Me = { user_name: string; persona: string; scope_employee: string | null; scope_name: string | null; scope_title: string | null;
  visible_employees: number; demo_override: boolean; tabs: string[] };
type Msg = { role: "user" | "bot"; text: string; sql?: string; columns?: string[]; rows?: any[][]; pending?: boolean };

export default function App() {
  const [me, setMe] = useState<Me | null>(null);
  const [meErr, setMeErr] = useState("");
  const [epoch, setEpoch] = useState(0); // bump to refetch every page after a persona switch
  const parseHash = () => { const [t, qs] = location.hash.replace(/^#\/?/, "").split("?"); return { t: t || "overview", p: new URLSearchParams(qs).get("p") }; };
  const [tab, setTab] = useState(() => parseHash().t);
  const [dockOpen, setDockOpen] = useState(false);
  const [person, setPerson] = useState<string | null>(() => parseHash().p);
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [conv, setConv] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const loadMe = useCallback(() => api<Me>("/api/me").then(setMe).catch((e) => setMeErr(String(e.message || e))), []);
  useEffect(() => { loadMe(); }, [loadMe]);
  useEffect(() => {
    const on = () => { const h = parseHash(); setTab(h.t); if (h.p) setPerson(h.p); };
    window.addEventListener("hashchange", on);
    return () => window.removeEventListener("hashchange", on);
  }, []);
  const go = (t: string) => { location.hash = `/${t}`; setTab(t); setDockOpen(false); };

  const ask = async (q: string) => {
    if (!q.trim() || busy) return;
    setBusy(true);
    setMsgs((m) => [...m, { role: "user", text: q }, { role: "bot", text: "", pending: true }]);
    try {
      const r = await api<any>("/api/ask", { question: q, conversation_id: conv });
      setConv(r.conversation_id);
      setMsgs((m) => [...m.slice(0, -1), { role: "bot", text: r.text, sql: r.sql, columns: r.columns, rows: r.rows }]);
    } catch (e: any) {
      setMsgs((m) => [...m.slice(0, -1), { role: "bot", text: `Something went wrong calling Genie: ${e.message || e}` }]);
    } finally { setBusy(false); }
  };

  const asked = useRef(false);
  useEffect(() => {
    const q = new URLSearchParams(location.hash.split("?")[1]).get("q");
    if (me && q && !asked.current) { asked.current = true; ask(q); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [me]);

  const switched = async () => {
    setMsgs([]); setConv(null); setPerson(null);
    await loadMe();
    setEpoch((e) => e + 1);
  };

  if (meErr) return <div className="shell"><main><div className="alert">Couldn't load your identity: {meErr}</div></main></div>;
  if (!me) return <div className="shell"><Header me={null} tab={tab} go={go} onSwitched={switched} /><main><Skeleton /></main></div>;

  const known = tab in TABS ? tab : "overview";
  const offMenu = !me.tabs.includes(known);
  const suggestions = SUGGESTED[me.persona] ?? SUGGESTED.default;
  const chat = { msgs, busy, ask, suggestions, reset: () => { setMsgs([]); setConv(null); } };

  return (
    <div className="shell">
      <Header me={me} tab={known} go={go} onSwitched={switched} />
      <main key={epoch}>
        {offMenu && (
          <div className="note"><b>This page isn't in your menu.</b> The app hides it for your persona, but hiding a tab isn't
            what protects the data. The page still loads below, and Unity Catalog returns only what you're entitled to see.</div>
        )}
        {known === "overview" && <Overview me={me} />}
        {known === "directory" && <Directory open={setPerson} />}
        {known === "team" && <Team me={me} open={setPerson} />}
        {known === "comp" && <Comp />}
        {known === "ask" && <AskPage chat={chat} />}
        {known === "access" && <Access me={me} />}
      </main>
      {person && <PersonDrawer id={person} close={() => setPerson(null)} key={`${person}-${epoch}`} />}
      {known !== "ask" && (
        <>
          <button className="fab" onClick={() => setDockOpen((o) => !o)}>
            <span className="spark"><Spark /></span>{dockOpen ? "Close" : "Ask AI"}
          </button>
          <div className={`dock ${dockOpen ? "open" : ""}`}>
            <div className="dockhead">
              <div><span className="aibadge"><Spark />GENIE</span><div style={{ marginTop: 6 }}><b>Ask People Insights</b></div>
                <div className="muted small">Answers run as you, under your access.</div></div>
              <div style={{ display: "flex", gap: 12 }}>
                <button className="link" onClick={() => go("ask")}>Full screen</button>
                <button className="link" onClick={() => setDockOpen(false)}>Close</button>
              </div>
            </div>
            <div className="dockbody"><Chat chat={chat} /></div>
            <div className="dockfoot"><AskBar chat={chat} /></div>
          </div>
        </>
      )}
    </div>
  );
}

// ------------------------------------------------------------------ header + demo persona menu
function Header({ me, tab, go, onSwitched }: { me: Me | null; tab: string; go: (t: string) => void; onSwitched: () => Promise<void> }) {
  const [open, setOpen] = useState(false);
  const [persona, setPersona] = useState<string>("");
  const [manager, setManager] = useState("W00030");
  const [saving, setSaving] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => { if (me) { setPersona(me.persona); if (me.persona === "people_manager" && me.scope_employee) setManager(me.scope_employee); } }, [me]);
  useEffect(() => {
    const on = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false); };
    document.addEventListener("mousedown", on);
    return () => document.removeEventListener("mousedown", on);
  }, []);

  const apply = async (reset = false) => {
    setSaving(true);
    try {
      await api("/api/persona", reset ? {} : { persona, manager: persona === "people_manager" ? manager : null });
      setOpen(false);
      await onSwitched();
    } finally { setSaving(false); }
  };

  const p = me ? PERSONAS[me.persona] : null;
  const scope = me?.persona === "people_manager" && me.scope_name ? ` · ${me.scope_name}'s line` : " · All employees";
  return (
    <header>
      <div className="brand"><span className="mark" /><b>People Insights</b><span className="aibadge"><Spark />AI</span></div>
      <nav>
        {(me?.tabs ?? ["overview"]).map((t) => (
          <button key={t} className={t === tab ? "on" : ""} onClick={() => go(t)}>{TABS[t]}</button>
        ))}
      </nav>
      <div className="who" ref={ref}>
        <button className="whobtn" onClick={() => setOpen((o) => !o)}>
          <div className="avatar">{(me?.user_name || "?")[0].toUpperCase()}</div>
          <div className="whotext">
            <div className="email">{me?.user_name ?? "Loading..."}</div>
            <div className="role">{me?.demo_override && <span className="demo-dot" title="Demo persona active" />}{p?.label ?? ""}{me ? scope : ""}</div>
          </div>
          <span className="chev">▾</span>
        </button>
        {open && me && (
          <div className="menu">
            <h4>Demo: act as a persona</h4>
            <div className="muted">Demo only. In production your groups and the HR hierarchy decide your persona.</div>
            {Object.entries(PERSONAS).map(([k, v]) => (
              <div key={k}>
                <button className={`opt ${persona === k ? "on" : ""}`} onClick={() => setPersona(k)}>
                  <span className="radio" /><div><b>{v.label}</b><span>{v.desc}</span></div>
                </button>
                {k === "people_manager" && persona === k && (
                  <div className="submgr">
                    {MANAGERS.map((m) => (
                      <label key={m.id}>
                        <input type="radio" checked={manager === m.id} onChange={() => setManager(m.id)} />
                        <span><b>{m.name}</b> <span className="muted small">{m.title} · {m.line} people</span></span>
                      </label>
                    ))}
                  </div>
                )}
              </div>
            ))}
            <div className="row">
              <button className="ghost" disabled={saving} onClick={() => apply(true)}>Reset to my access</button>
              <button className="primary" disabled={saving} onClick={() => apply()}>{saving ? "Switching..." : "Apply"}</button>
            </div>
          </div>
        )}
      </div>
    </header>
  );
}

function Skeleton() {
  return (<><div className="tiles">{[0, 1, 2, 3].map((i) => <div key={i} className="skel tile" />)}</div>
    <div className="grid2" style={{ marginTop: 24 }}><div className="skel block" /><div className="skel block" /></div></>);
}
const ErrorBox = ({ err }: { err?: string }) => (err ? <div className="alert">{err}</div> : null);

function ScopeBanner({ me }: { me: Me }) {
  const mgr = me.persona === "people_manager";
  return (
    <div className={`scope ${mgr ? "mgr" : ""}`}>
      <Shield />
      <div className="grow">
        {mgr ? <><b>{me.scope_name}'s reporting line</b> <span className="muted">· {fmtInt(me.visible_employees)} people, including {me.scope_name?.split(" ")[0]}</span></>
             : <><b>All employees</b> <span className="muted">· {fmtInt(me.visible_employees)} people</span></>}
        <div className="muted small">Viewing as {PERSONAS[me.persona]?.label}. Rows and columns are filtered by Unity Catalog before they reach this app.</div>
      </div>
      <span className="pill navy">{PERSONAS[me.persona]?.desc}</span>
    </div>
  );
}

// ------------------------------------------------------------------ overview
function Overview({ me }: { me: Me }) {
  const { data, err, loading } = useLoad(() => api<any>("/api/overview"), []);
  const k = data?.kpis;
  const maxDept = Math.max(1, ...(data?.by_dept ?? []).map((d: Row) => Number(d.headcount)));
  const maxLvl = Math.max(1, ...(data?.by_level ?? []).map((d: Row) => Number(d.headcount)));
  return (
    <>
      <div className="eyebrow">Workforce today</div>
      <h1>{me.persona === "people_manager" ? `Your organization, ${me.scope_name?.split(" ")[0]}` : "Your workforce at a glance"}</h1>
      <p className="lede">Headcount, hiring and pay across the people you're entitled to see. Ask the AI assistant anything the tiles don't answer.</p>
      <ScopeBanner me={me} />
      <ErrorBox err={err} />
      {loading && !data ? <Skeleton /> : k && (
        <>
          <div className="tiles">
            <div className="tile"><div className="tk">Headcount</div><div className="tv">{fmtInt(k.headcount)}</div>
              <div className="ts">{k.departments} {Number(k.departments) === 1 ? "department" : "departments"} · {k.avg_tenure} yrs avg tenure</div></div>
            <div className="tile green"><div className="tk">Open requisitions</div><div className="tv">{fmtInt(k.open_reqs)}</div>
              <div className="ts">{me.persona === "people_manager" ? "where you or your managers hire" : "across the company"}</div></div>
            <div className="tile red"><div className="tk">Total compensation</div><div className="tv">{show(k.total_comp, money)}</div>
              <div className="ts">base + bonus target + equity</div></div>
            <div className="tile violet"><div className="tk">High performers</div>
              <div className="tv">{show(k.high_perf_share, (v) => `${Math.round(Number(v) * 100)}%`)}</div>
              <div className="ts">rated Exceeds or Exceptional, 2026</div></div>
          </div>
          <div className="grid2" style={{ marginTop: 24 }}>
            <div className="card">
              <div className="section-title" style={{ marginTop: 0 }}>Headcount by department</div>
              <div className="bars">
                {data.by_dept.map((d: Row) => (
                  <div className="brow" key={d.dept_name}><div className="lbl">{d.dept_name}</div>
                    <div className="bar"><i style={{ width: `${(Number(d.headcount) / maxDept) * 100}%` }} /></div>
                    <div className="val">{fmtInt(d.headcount)}</div></div>
                ))}
              </div>
            </div>
            <div className="card">
              <div className="section-title" style={{ marginTop: 0 }}>Headcount by job level</div>
              <div className="cols">
                {data.by_level.map((d: Row) => (
                  <div className="col" key={d.job_level}><b>{fmtInt(d.headcount)}</b>
                    <i style={{ height: `${Math.max(2, (Number(d.headcount) / maxLvl) * 140)}px` }} /><span>{d.job_level}</span></div>
                ))}
              </div>
              <div className="muted small" style={{ marginTop: 12 }}>L3-L5 individual contributors · L6 managers · L7 senior managers · L8+ executives</div>
            </div>
          </div>
        </>
      )}
    </>
  );
}

// ------------------------------------------------------------------ directory + profile drawer
function Directory({ open }: { open: (id: string) => void }) {
  const [q, setQ] = useState("");
  const [term, setTerm] = useState("");
  useEffect(() => { const t = setTimeout(() => setTerm(q), 300); return () => clearTimeout(t); }, [q]);
  const { data, err, loading } = useLoad(() => api<Row[]>(`/api/directory?q=${encodeURIComponent(term)}`), [term]);
  return (
    <>
      <div className="eyebrow">People directory</div>
      <h1>Find anyone you're entitled to see</h1>
      <p className="lede">Columns carry a sensitivity tier. Anything above your tier shows as restricted, and the restriction comes from Unity Catalog, not this page.</p>
      <div className="toolbar">
        <div className="search"><SearchIcon /><input placeholder="Search by name, title, department or ID" value={q} onChange={(e) => setQ(e.target.value)} /></div>
      </div>
      <ErrorBox err={err} />
      <div className="table">
        <table>
          <thead><tr><th>Employee</th><th>Level</th><th>Department</th><th>Country</th><th>Hire date</th>
            <th>Home address <TierTag n={3} /></th><th>SSN <TierTag n={4} /></th></tr></thead>
          <tbody>
            {loading && !data && [0, 1, 2, 3, 4, 5].map((i) => <tr key={i}><td colSpan={7}><div className="skel" style={{ height: 22 }} /></td></tr>)}
            {data?.map((r) => (
              <tr key={r.employee_id} className="click" onClick={() => open(r.employee_id)}>
                <td><div className="person"><Ini name={r.full_name} /><div><b>{r.full_name}</b><span>{r.job_title}</span></div></div></td>
                <td>{r.job_level}</td><td>{r.dept_name}</td><td>{r.country}</td><td>{r.hire_date}</td>
                <td>{show(r.home_address)}</td><td>{show(r.ssn, (v) => <code>{v}</code>)}</td>
              </tr>
            ))}
            {data && !data.length && <tr><td colSpan={7}><div className="muted" style={{ padding: 12 }}>No one you can see matches "{term}".</div></td></tr>}
          </tbody>
        </table>
      </div>
      {data && data.length === 200 && <div className="muted small" style={{ marginTop: 8 }}>Showing the first 200 people. Search to narrow it down.</div>}
    </>
  );
}

function PersonDrawer({ id, close }: { id: string; close: () => void }) {
  const { data, err } = useLoad(() => api<any>(`/api/person/${id}`), [id]);
  const p = data?.person, c = data?.comp, perf = data?.performance;
  const medical = (data?.leave ?? []).find((l: Row) => l.medical_leave_reason && l.medical_leave_reason !== "****")?.medical_leave_reason
    ?? (data?.leave ?? []).find((l: Row) => l.medical_leave_reason)?.medical_leave_reason ?? null;
  return (
    <>
      <div className="scrim" onClick={close} />
      <aside className="drawer">
        <div className="dhead">
          <button className="close" onClick={close} aria-label="Close">✕</button>
          {p ? <><Ini name={p.full_name} /><h2>{p.full_name}</h2><div className="sub">{p.job_title} · {p.dept_name} · {p.employee_id}</div></>
             : <div className="sub">{err ? "Not available" : "Loading..."}</div>}
        </div>
        <ErrorBox err={err} />
        {p && (
          <>
            <section className="dsec"><h3>Employment <TierTag n={1} /></h3>
              <dl className="kv"><dt>Level</dt><dd>{p.job_level}</dd><dt>Manager</dt><dd>{p.manager_name ?? "None"}</dd>
                <dt>Country</dt><dd>{p.country}</dd><dt>Hire date</dt><dd>{p.hire_date}</dd><dt>Work email</dt><dd>{p.work_email}</dd></dl></section>
            <section className="dsec"><h3>Performance <TierTag n={2} /></h3>
              <dl className="kv"><dt>2026 rating</dt><dd>{ratingPill(perf?.rating)}</dd><dt>Promotions</dt><dd>{show(perf?.promotion_history)}</dd></dl>
              {perf && !masked(perf.review_text) ? <div className="quote">"{perf.review_text}"</div> : <div style={{ marginTop: 10 }}><Restricted label="Review text restricted" /></div>}
            </section>
            <section className="dsec"><h3>Compensation <TierTag n={3} /></h3>
              <dl className="kv"><dt>Base salary</dt><dd>{show(c?.base_salary, moneyFull)}</dd><dt>Bonus target</dt><dd>{show(c?.bonus_target, moneyFull)}</dd>
                <dt>Equity grant</dt><dd>{show(c?.equity_grant, moneyFull)}</dd><dt>Total comp</dt><dd><b>{show(c?.total_comp, moneyFull)}</b></dd></dl></section>
            <section className="dsec"><h3>Personal <TierTag n={3} /></h3>
              <dl className="kv"><dt>Home address</dt><dd>{show(p.home_address)}</dd><dt>Personal phone</dt><dd>{show(p.personal_phone)}</dd>
                <dt>Date of birth</dt><dd>{show(p.date_of_birth)}</dd></dl></section>
            <section className="dsec"><h3>Highly restricted <TierTag n={4} /></h3>
              <dl className="kv"><dt>SSN</dt><dd>{show(p.ssn, (v) => <code>{v}</code>)}</dd>
                <dt>Medical leave reason</dt><dd>{data.leave.length ? show(medical) : <span className="muted">No leave on record</span>}</dd></dl></section>
            {data.training.length > 0 && (
              <section className="dsec"><h3>Learning <TierTag n={2} /></h3>
                <table><tbody>{data.training.map((t: Row, i: number) => (
                  <tr key={i}><td>{t.course_name}</td><td>{show(t.completion_status)}</td><td className="num">{show(t.assessment_score)}</td></tr>
                ))}</tbody></table></section>
            )}
          </>
        )}
      </aside>
    </>
  );
}

// ------------------------------------------------------------------ my team
function Team({ me, open }: { me: Me; open: (id: string) => void }) {
  const { data, err, loading } = useLoad(() => api<any>("/api/team"), []);
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const model = useMemo(() => {
    if (!data) return null;
    const people: Row[] = data.people;
    const byId = new Map(people.map((p) => [p.employee_id, p]));
    const kids = new Map<string, Row[]>();
    people.forEach((p) => { if (p.manager_id && byId.has(p.manager_id)) kids.set(p.manager_id, [...(kids.get(p.manager_id) ?? []), p]); });
    const below = (id: string): Row[] => (kids.get(id) ?? []).flatMap((k) => [k, ...below(k.employee_id)]);
    const root = byId.get(me.scope_employee ?? "");
    const directs = root ? kids.get(root.employee_id) ?? [] : [];
    const leaders = directs.filter((d) => (kids.get(d.employee_id) ?? []).length);
    const ics = directs.filter((d) => !(kids.get(d.employee_id) ?? []).length);
    const groups = [
      ...leaders.map((l) => ({ lead: l, members: below(l.employee_id) })),
      ...(ics.length ? [{ lead: null as Row | null, members: ics }] : []),
    ];
    const comps = people.map((p) => p.total_comp).filter((v) => !masked(v)).map(Number);
    const rated = people.map((p) => p.rating).filter((r) => !masked(r));
    return { root, groups, size: people.length - 1, total: comps.length ? comps.reduce((a, b) => a + b, 0) : null,
      high: rated.length ? rated.filter((r) => r === "Exceeds" || r === "Exceptional").length / rated.length : null };
  }, [data, me.scope_employee]);

  const Member = ({ p }: { p: Row }) => (
    <div className="member" onClick={() => open(p.employee_id)}>
      <div className="nm"><b>{p.full_name}</b><span>{p.job_title} · {p.job_level}</span></div>
      {ratingPill(p.rating)}<div className="money">{show(p.total_comp, money)}</div>
    </div>
  );
  const openReqs = (data?.requisitions ?? []).filter((r: Row) => r.status === "Open").length;

  return (
    <>
      <div className="eyebrow">My team</div>
      <h1>Everyone in your reporting line</h1>
      <p className="lede">Your direct and indirect reports at every level. Unity Catalog's reporting-line row filter decides who appears here, so people outside your line, including your own manager, never reach this page.</p>
      <ErrorBox err={err} />
      {loading && !data && <Skeleton />}
      {model && !model.root && <div className="empty">No reporting line for this identity. My Team is for people managers.</div>}
      {model?.root && (
        <>
          <div className="orgroot">
            <Ini name={model.root.full_name} />
            <div className="grow"><b>{model.root.full_name}</b><span>{model.root.job_title} · {model.root.dept_name}</span></div>
            <div className="stat"><b>{model.size}</b><div className="muted" style={{ color: "#b9c8cd" }}>people in line</div></div>
          </div>
          <div className="tiles" style={{ marginBottom: 24 }}>
            <div className="tile"><div className="tk">Team size</div><div className="tv">{model.size}</div><div className="ts">{model.groups.length} teams</div></div>
            <div className="tile red"><div className="tk">Team total comp</div><div className="tv">{model.total === null ? <Restricted /> : money(model.total)}</div><div className="ts">including you</div></div>
            <div className="tile violet"><div className="tk">High performers</div><div className="tv">{model.high === null ? <Restricted /> : `${Math.round(model.high * 100)}%`}</div><div className="ts">Exceeds or Exceptional</div></div>
            <div className="tile green"><div className="tk">Open requisitions</div><div className="tv">{openReqs}</div><div className="ts">you or your managers hiring</div></div>
          </div>
          <div className="groups">
            {model.groups.map((g) => {
              const key = g.lead?.employee_id ?? "ics";
              const list = expanded[key] ? g.members : g.members.slice(0, 6);
              return (
                <div className="group" key={key}>
                  {g.lead ? (
                    <div className="ghead" onClick={() => open(g.lead!.employee_id)}>
                      <Ini name={g.lead.full_name} /><div className="grow"><b>{g.lead.full_name}</b><span>{g.lead.job_title} · {g.members.length} reports</span></div>
                      <div className="money" style={{ fontWeight: 700 }}>{show(g.lead.total_comp, money)}</div>
                    </div>
                  ) : <div className="ghead"><div className="grow"><b>Direct reports</b><span>{g.members.length} individual contributors</span></div></div>}
                  {list.map((p) => <Member key={p.employee_id} p={p} />)}
                  {g.members.length > 6 && (
                    <button className="more" onClick={() => setExpanded((e) => ({ ...e, [key]: !e[key] }))}>
                      {expanded[key] ? "Show fewer" : `Show all ${g.members.length}`}</button>
                  )}
                </div>
              );
            })}
          </div>
          <div className="section-title">Requisitions <span>where you or someone in your line is the hiring manager</span></div>
          <div className="table">
            <table><thead><tr><th>Requisition</th><th>Role</th><th>Hiring manager</th><th>Status</th><th className="num">Applicants</th></tr></thead>
              <tbody>{data.requisitions.map((r: Row) => (
                <tr key={r.requisition_id}><td><code>{r.requisition_id}</code></td><td>{r.job_title}</td><td>{r.hiring_manager}</td>
                  <td><span className={`pill ${r.status === "Open" ? "green" : r.status === "On hold" ? "amber" : "navy"}`}>{r.status}</span></td>
                  <td className="num">{r.applicants}</td></tr>
              ))}
                {!data.requisitions.length && <tr><td colSpan={5} className="muted">No requisitions in your line.</td></tr>}
              </tbody></table>
          </div>
        </>
      )}
    </>
  );
}

// ------------------------------------------------------------------ compensation
function Comp() {
  const { data, err, loading } = useLoad(() => api<any>("/api/comp"), []);
  const depts: Row[] = data?.by_dept ?? [];
  const levels: Row[] = data?.by_level ?? [];
  const head = depts.reduce((a, d) => a + Number(d.headcount), 0);
  const allMasked = depts.length > 0 && depts.every((d) => masked(d.total_comp));
  const total = allMasked ? null : depts.reduce((a, d) => a + Number(d.total_comp ?? 0), 0);
  const maxAvg = Math.max(1, ...depts.map((d) => Number(d.avg_total_comp ?? 0)));
  const maxLvl = Math.max(1, ...levels.map((d) => Number(d.avg_total_comp ?? 0)));
  return (
    <>
      <div className="eyebrow">Total rewards</div>
      <h1>Compensation across the organization</h1>
      <p className="lede">From the governed <code>mv_total_comp</code> metric view. The metric view carries no policy of its own; the masks on the compensation table it reads decide what each person gets back.</p>
      <ErrorBox err={err} />
      {loading && !data ? <Skeleton /> : data && (
        <>
          <div className="tiles">
            <div className="tile red"><div className="tk">Total payroll</div><div className="tv">{total === null ? <Restricted /> : money(total)}</div><div className="ts">base + bonus target + equity</div></div>
            <div className="tile"><div className="tk">Average total comp</div><div className="tv">{total === null ? <Restricted /> : money(total / Math.max(1, head))}</div><div className="ts">per employee</div></div>
            <div className="tile"><div className="tk">Headcount</div><div className="tv">{fmtInt(head)}</div><div className="ts">{depts.length} departments</div></div>
            <div className="tile violet"><div className="tk">Top level max</div><div className="tv">{show(levels[levels.length - 1]?.max_total_comp, money)}</div><div className="ts">{levels[levels.length - 1]?.job_level ?? ""}</div></div>
          </div>
          <div className="grid2" style={{ marginTop: 24 }}>
            <div className="card">
              <div className="section-title" style={{ marginTop: 0 }}>Average total comp by department <span>bars on a square-root scale</span></div>
              <div className="bars">{depts.map((d) => (
                <div className="brow" key={d.department}><div className="lbl">{d.department}</div>
                  <div className="bar lava"><i style={{ width: masked(d.avg_total_comp) ? 0 : `${Math.sqrt(Number(d.avg_total_comp) / maxAvg) * 100}%` }} /></div>
                  <div className="val">{show(d.avg_total_comp, money)}</div></div>
              ))}</div>
            </div>
            <div className="card">
              <div className="section-title" style={{ marginTop: 0 }}>By job level</div>
              <table><thead><tr><th>Level</th><th className="num">People</th><th className="num">Avg base</th><th className="num">Avg total</th><th style={{ width: "30%" }} /></tr></thead>
                <tbody>{levels.map((l) => (
                  <tr key={l.job_level}><td><b>{l.job_level}</b></td><td className="num">{fmtInt(l.headcount)}</td>
                    <td className="num">{show(l.avg_base, money)}</td><td className="num"><b>{show(l.avg_total_comp, money)}</b></td>
                    <td><div className="bar lava"><i style={{ width: masked(l.avg_total_comp) ? 0 : `${Math.sqrt(Number(l.avg_total_comp) / maxLvl) * 100}%` }} /></div></td></tr>
                ))}</tbody></table>
            </div>
          </div>
        </>
      )}
    </>
  );
}

// ------------------------------------------------------------------ my access
function Access({ me }: { me: Me }) {
  const { data, err, loading } = useLoad(() => api<any>("/api/access"), []);
  return (
    <>
      <div className="eyebrow">My access</div>
      <h1>What you can see, and why</h1>
      <p className="lede">Every column in the HR data carries a sensitivity tier. Unity Catalog checks your persona against that tier on every query, including the ones the AI assistant writes for you.</p>
      <ScopeBanner me={me} />
      <ErrorBox err={err} />
      <div className="card">
        <div className="section-title" style={{ marginTop: 0 }}>Sensitivity tiers <span>checked live against the data, as you</span></div>
        {loading && !data && <div className="skel block" />}
        {data?.tiers.map((t: Row, i: number) => (
          <div className="tierrow" key={t.tier}>
            <div><TierTag n={(i + 1) as 1 | 2 | 3 | 4} /></div>
            <div className="muted">{t.examples}</div>
            <div className={`state ${t.clear ? "clear" : "masked"}`}>{t.clear ? <><Check />Visible</> : <><Lock />Masked</>}</div>
          </div>
        ))}
      </div>
      <div className="section-title">Rows you can see</div>
      <div className="card">
        {me.persona === "people_manager"
          ? <>Only people in <b>{me.scope_name}</b>'s reporting line ({fmtInt(me.visible_employees)} people). Recruiting data is limited to requisitions where you or someone in your line is the hiring manager.</>
          : <>All {fmtInt(me.visible_employees)} employees. Your persona isn't row-filtered; sensitive columns are handled by the tier masks above.</>}
        <div className="muted" style={{ marginTop: 10 }}>Pages in your menu: {me.tabs.map((t) => TABS[t]).join(", ")}.</div>
      </div>
      <div className="section-title">How it works</div>
      <div className="how">
        <div className="step"><div className="n">01 · TAG</div><b>Columns are tagged once</b><p>A governed tag, <code>hr_pii_demo_tag</code>, marks each column internal, confidential, restricted or highly restricted. Employee ID columns also carry a reporting-line scope tag.</p></div>
        <div className="step"><div className="n">02 · POLICY</div><b>Four policies cover every table</b><p>Three column-mask policies (one per protected tier) and one reporting-line row filter, set once on the catalog. New tables are covered as soon as their columns are tagged.</p></div>
        <div className="step"><div className="n">03 · AS YOU</div><b>Everything runs as you</b><p>The app forwards your sign-in to Databricks, so every page and every AI answer runs under your identity. The app has no data access of its own.</p></div>
      </div>
    </>
  );
}

// ------------------------------------------------------------------ ask
type Chat = { msgs: Msg[]; busy: boolean; ask: (q: string) => void; suggestions: string[]; reset: () => void };

function AskBar({ chat }: { chat: Chat }) {
  const [q, setQ] = useState("");
  const submit = () => { if (q.trim()) { chat.ask(q); setQ(""); } };
  return (
    <div className="askbar">
      <input placeholder="Ask about headcount, compensation, hiring, performance..." value={q} onChange={(e) => setQ(e.target.value)}
        onKeyDown={(e) => e.key === "Enter" && submit()} disabled={chat.busy} />
      <button className="primary" onClick={submit} disabled={chat.busy || !q.trim()}>Ask</button>
    </div>
  );
}

function Chat({ chat }: { chat: Chat }) {
  const end = useRef<HTMLDivElement>(null);
  useEffect(() => { end.current?.scrollIntoView({ behavior: "smooth", block: "end" }); }, [chat.msgs]);
  if (!chat.msgs.length) {
    return (<><div className="muted" style={{ margin: "4px 0 10px" }}>Try one of these:</div>
      <div className="chips">{chat.suggestions.map((s) => <button key={s} className="chip" onClick={() => chat.ask(s)}>{s}</button>)}</div></>);
  }
  return (
    <div className="chat">
      {chat.msgs.map((m, i) => m.role === "user" ? <div key={i} className="bubble user">{m.text}</div> : <BotBubble key={i} m={m} />)}
      <div ref={end} />
    </div>
  );
}

function BotBubble({ m }: { m: Msg }) {
  if (m.pending) return <div className="bubble bot"><div className="botlabel"><Spark />GENIE</div><span className="thinking"><i /><i /><i /> Querying your data as you</span></div>;
  const { body, note } = renderMd(m.text || "");
  return (
    <div className="bubble bot">
      <div className="botlabel"><Spark />GENIE · RAN AS YOU</div>
      <div className="md" dangerouslySetInnerHTML={{ __html: body }} />
      {m.columns && m.columns.length > 0 && m.rows && m.rows.length > 0 && (
        <div className="result"><table><thead><tr>{m.columns.map((c) => <th key={c}>{c.replace(/_/g, " ")}</th>)}</tr></thead>
          <tbody>{m.rows.slice(0, 20).map((r, i) => <tr key={i}>{r.map((v, j) => <td key={j}>{masked(v) ? <Restricted /> : cell(v)}</td>)}</tr>)}</tbody></table></div>
      )}
      {note && <div className="md"><div className="footnote"><Shield /><span dangerouslySetInnerHTML={{ __html: note }} /></div></div>}
      {m.sql && <details className="sql"><summary>SQL Genie ran</summary><pre>{m.sql}</pre></details>}
    </div>
  );
}

function AskPage({ chat }: { chat: Chat }) {
  return (
    <>
      <div className="askhero">
        <span className="aibadge"><Spark />AI · POWERED BY DATABRICKS GENIE</span>
        <h1>Ask anything about your workforce</h1>
        <p>Plain-English questions become SQL that runs as you. The same question returns different answers for different people, because Unity Catalog applies your masks and row filters before the AI sees any data.</p>
      </div>
      <div className="askpanel"><Chat chat={chat} /></div>
      <AskBar chat={chat} />
      {chat.msgs.length > 0 && <div style={{ marginTop: 10 }}><button className="link" onClick={chat.reset}>Start a new conversation</button></div>}
    </>
  );
}
