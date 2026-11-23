#!/usr/bin/env python3
"""Generate docs/abac-design.excalidraw: three frames that explain the ABAC design.

  1 - Sensitivity tiers          (tier, tag value, example columns, who sees it in clear)
  2 - Tags, policies, functions  (how a tag on a column becomes a mask or filter at query time)
  3 - One row filter             (the reporting_line scope tag + reporting_closure)

Usage: python3 scripts/make_design_diagram.py   (writes docs/abac-design.excalidraw)
Open it at excalidraw.com; select a frame title, then Export image > Only selected, to get one PNG per frame.
"""
import json
import random
from pathlib import Path

NAVY, NAVY2, LAVA, OAT, SLATE, LINE = "#1B3139", "#24434d", "#FF3621", "#F9F7F4", "#5A6F77", "#C9C4BA"
WHITE, GREEN, GREEN_BG, VIOLET, VIOLET_BG = "#ffffff", "#00A972", "#d6f5e9", "#7B61FF", "#ece8ff"
TIER = {  # fill, text color
    "internal": ("#e3ebee", NAVY),
    "confidential": ("#fff1cc", "#7a5200"),
    "restricted": ("#ffe4df", "#b3261e"),
    "highly_restricted": ("#2b1b1b", "#ffb4a8"),
}
FONT_BODY, FONT_HAND, FONT_CODE = 2, 5, 3

elements: list[dict] = []
_frame = None
_n = 0


def _id(prefix: str) -> str:
    global _n
    _n += 1
    return f"{prefix}{_n:04d}"


def _base(kind: str, x, y, w, h, **kw) -> dict:
    return {
        "id": _id(kind[:2]), "type": kind, "x": x, "y": y, "width": w, "height": h, "angle": 0,
        "strokeColor": kw.get("stroke", NAVY), "backgroundColor": kw.get("bg", "transparent"),
        "fillStyle": "solid", "strokeWidth": kw.get("sw", 2),
        "strokeStyle": "dashed" if kw.get("dashed") else "solid", "roughness": kw.get("rough", 1), "opacity": 100,
        "groupIds": [], "frameId": _frame, "roundness": {"type": 3} if kw.get("round", True) else None,
        "seed": random.randint(1, 2**31), "version": 1, "versionNonce": random.randint(1, 2**31),
        "isDeleted": False, "boundElements": None, "updated": 1, "link": None, "locked": False,
    }


def rect(x, y, w, h, bg="transparent", stroke=NAVY, **kw):
    e = _base("rectangle", x, y, w, h, bg=bg, stroke=stroke, **kw)
    elements.append(e)
    return e


def text(x, y, s, fs=18, color=NAVY, w=None, align="left", font=FONT_BODY):
    lines = s.split("\n")
    est_w = max(len(l) for l in lines) * fs * (0.6 if font == FONT_CODE else 0.53)
    h = len(lines) * fs * 1.25
    e = _base("text", x, y, w or est_w, h, stroke=color, sw=1, round=False)
    e.update({"text": s, "originalText": s, "fontSize": fs, "fontFamily": font, "textAlign": align,
              "verticalAlign": "top", "containerId": None, "autoResize": w is None, "lineHeight": 1.25})
    elements.append(e)
    return e


def ctext(x, y, w, h, s, fs=18, color=NAVY, font=FONT_BODY):
    """Text centered in a box."""
    lines = s.split("\n")
    th = len(lines) * fs * 1.25
    return text(x, y + (h - th) / 2, s, fs, color, w=w, align="center", font=font)


def box(x, y, w, h, s, bg=WHITE, stroke=NAVY, fs=18, color=NAVY, font=FONT_BODY, **kw):
    rect(x, y, w, h, bg, stroke, **kw)
    ctext(x + 8, y, w - 16, h, s, fs, color, font)


def chip(x, y, value, fs=14):
    bg, fg = TIER[value]
    w = len(value) * fs * 0.62 + 20
    rect(x, y, w, fs * 1.9, bg, bg, sw=1, rough=0)
    ctext(x, y, w, fs * 1.9, value, fs, fg, FONT_CODE)
    return w


def arrow(x1, y1, x2, y2, color=NAVY, dashed=False, label=None, fs=15):
    e = _base("arrow", x1, y1, x2 - x1, y2 - y1, stroke=color, dashed=dashed, round=False)
    e.update({"points": [[0, 0], [x2 - x1, y2 - y1]], "lastCommittedPoint": None, "startBinding": None,
              "endBinding": None, "startArrowhead": None, "endArrowhead": "arrow", "elbowed": False})
    e["roundness"] = {"type": 2}
    elements.append(e)
    if label:
        text((x1 + x2) / 2 - len(label) * fs * 0.27, (y1 + y2) / 2 - fs * 1.6, label, fs, SLATE)


def frame(x, y, w, h, name):
    global _frame
    f = _base("frame", x, y, w, h, stroke="#bbb", round=False)
    f["name"] = name
    f["frameId"] = None
    elements.append(f)
    _frame = f["id"]
    return f


def heading(x, y, title, sub):
    text(x, y, title, 36, NAVY, font=FONT_HAND)
    text(x, y + 52, sub, 19, SLATE)


# ============================================================================ frame 1: tiers
random.seed(7)
FX, FY = 0, 0
frame(FX, FY, 1560, 960, "1 - Sensitivity tiers")
heading(FX + 50, FY + 40, "Four sensitivity tiers, one governed tag",
        "Every column carries hr_pii_demo_tag. The tag value decides who sees the column in clear.")

cols = [("Tier", 190), ("Tag value", 230), ("Example columns", 640), ("Who sees it in clear", 400)]
tx, ty = FX + 50, FY + 160
x = tx
for name, w in cols:
    rect(x, ty, w, 56, NAVY, NAVY, rough=0, round=False)
    ctext(x, ty, w, 56, name, 19, WHITE)
    x += w

rows = [
    ("internal", "Tier 1\nInternal",
     "Name, job title, department, job level,\ncountry, hire date, work email, employee ID,\nleave type, course name",
     "Everyone in HR"),
    ("confidential", "Tier 2\nConfidential",
     "Performance rating, review text, promotion\nhistory, leave balance, training scores,\ncandidate name, interview notes, resume text",
     "People managers (own line only)\nHR trusted (HRBP)\nER / Legal / Benefits"),
    ("restricted", "Tier 3\nRestricted",
     "Base salary, bonus target, equity grant,\ncomp grade, home address, date of birth,\npersonal phone, emergency contact",
     "People managers (own line only)\nHR trusted (HRBP)\nER / Legal / Benefits"),
    ("highly_restricted", "Tier 4\nHighly restricted",
     "SSN, bank routing number, medical leave\nreason, ADA accommodation, background\ncheck result, ER investigation notes",
     "ER / Legal / Benefits only"),
]
y = ty + 56
for value, tier, examples, who in rows:
    bg, fg = TIER[value]
    rh = 150
    x = tx
    rect(x, y, cols[0][1], rh, bg, LINE, rough=0, round=False, sw=1)
    ctext(x, y, cols[0][1], rh, tier, 21, fg)
    x += cols[0][1]
    rect(x, y, cols[1][1], rh, WHITE, LINE, rough=0, round=False, sw=1)
    cw = len(value) * 16 * 0.62 + 20
    chip(x + (cols[1][1] - cw) / 2, y + rh / 2 - 15, value, 16)
    x += cols[1][1]
    rect(x, y, cols[2][1], rh, WHITE, LINE, rough=0, round=False, sw=1)
    text(x + 20, y + (rh - 3 * 18 * 1.25) / 2, examples, 18, NAVY)
    x += cols[2][1]
    rect(x, y, cols[3][1], rh, WHITE, LINE, rough=0, round=False, sw=1)
    n = who.count("\n") + 1
    text(x + 20, y + (rh - n * 18 * 1.25) / 2, who, 18, NAVY)
    y += rh

text(tx, y + 24, "HR analysts (the default persona) see Tier 1 only. Masked text comes back as ****, masked numbers and "
     "dates as NULL,\nso sums, averages and filters on masked columns return nothing.", 17, SLATE)

# ============================================================================ frame 2: tags -> policies -> functions
FX, FY = 1700, 0
frame(FX, FY, 2480, 1180, "2 - Tags, policies and functions")
heading(FX + 50, FY + 40, "How a tag on a column becomes a mask or a filter",
        "Policies match columns by tag, never by name. Functions hold the logic. Everything is evaluated for the person "
        "running the query.")

top = FY + 170
# --- A: governed tags
ax, aw = FX + 50, 330
text(ax, top, "1  Governed tags", 24, LAVA, font=FONT_HAND)
text(ax, top + 34, "account level, allowed values only", 16, SLATE)
rect(ax, top + 70, aw, 300, OAT, NAVY)
text(ax + 20, top + 88, "hr_pii_demo_tag", 20, NAVY, font=FONT_CODE)
for i, v in enumerate(["internal", "confidential", "restricted", "highly_restricted"]):
    chip(ax + 20, top + 128 + i * 52, v, 16)
rect(ax, top + 400, aw, 130, OAT, NAVY)
text(ax + 20, top + 418, "hr_scope_demo_tag", 20, NAVY, font=FONT_CODE)
rect(ax + 20, top + 458, 150, 30, LAVA, LAVA, sw=1, rough=0)
ctext(ax + 20, top + 458, 150, 30, "reporting_line", 15, WHITE, FONT_CODE)
text(ax + 20, top + 496, "on employee key columns only", 15, SLATE)

# --- B: catalog + tagged tables
bx, bw = FX + 470, 560
text(bx, top, "2  Columns tagged in the catalog", 24, LAVA, font=FONT_HAND)
text(bx, top + 34, "glb, tr, ta, lrn schemas (bronze / silver / gold)", 16, SLATE)
rect(bx, top + 70, bw, 690, WHITE, NAVY, dashed=True)
tables = [
    ("glb_silver.employees", [("full_name", "internal"), ("home_address", "restricted"), ("ssn", "highly_restricted")]),
    ("glb_silver.performance", [("rating", "confidential"), ("review_text", "confidential")]),
    ("tr_silver.compensation", [("base_salary", "restricted"), ("equity_grant", "restricted")]),
    ("ta_silver.applications", [("interview_notes", "confidential")]),
    ("lrn_silver.training_records", [("assessment_score", "confidential")]),
]
y = top + 90
for tname, colset in tables:
    h = 46 + len(colset) * 36
    rect(bx + 20, y, bw - 40, h, OAT, NAVY2, sw=1)
    text(bx + 36, y + 10, tname, 17, NAVY, font=FONT_CODE)
    for i, (c, v) in enumerate(colset):
        text(bx + 50, y + 44 + i * 36, c, 15, NAVY, font=FONT_CODE)
        chip(bx + 290, y + 40 + i * 36, v, 13)
    y += h + 14

# --- C: policies
cx, cw = FX + 1110, 400
text(cx, top, "3  Four policies, set once", 24, LAVA, font=FONT_HAND)
text(cx, top + 34, "ON CATALOG, TO account users", 16, SLATE)
pols = [
    ("hr_demo_mask_confidential", "COLUMN MASK  match tier = confidential"),
    ("hr_demo_mask_restricted", "COLUMN MASK  match tier = restricted"),
    ("hr_demo_mask_highly_restricted", "COLUMN MASK  match tier = highly_restricted"),
    ("hr_demo_reporting_line_row_filter", "ROW FILTER  match scope = reporting_line"),
]
for i, (pn, desc) in enumerate(pols):
    py = top + 70 + i * 140
    rect(cx, py, cw, 112, WHITE, LAVA if i == 3 else NAVY)
    text(cx + 18, py + 18, pn, 16, NAVY, font=FONT_CODE)
    text(cx + 18, py + 56, desc, 15, SLATE)

# --- D: functions
dx, dw = FX + 1590, 400
text(dx, top, "4  Functions hold the logic", 24, LAVA, font=FONT_HAND)
text(dx, top + 34, "glb_governance schema (untagged)", 16, SLATE)
funcs = [
    ("mask_confidential(val)", "clear for manager, trusted, ER"),
    ("mask_restricted(val)", "clear for manager, trusted, ER"),
    ("mask_highly_restricted(val)", "clear for ER / Legal only"),
    ("rf_reporting_line(emp)", "managers: own line only"),
]
for i, (fn, desc) in enumerate(funcs):
    fy = top + 70 + i * 140
    rect(dx, fy, dw, 112, VIOLET_BG, VIOLET)
    text(dx + 18, fy + 18, fn, 16, NAVY, font=FONT_CODE)
    text(dx + 18, fy + 56, desc, 15, SLATE)
    arrow(cx + cw, fy + 56, dx, fy + 56, NAVY, label="calls" if i == 0 else None)
# current_persona
pyy = top + 640
rect(dx, pyy, dw, 230, NAVY, NAVY)
text(dx + 18, pyy + 16, "current_persona()", 18, WHITE, font=FONT_CODE)
text(dx + 18, pyy + 56, "1. HR-DBX-ER-LEGAL group  ->  er_legal\n2. HR-DBX-TRUSTED group  ->  hr_trusted\n"
     "3. has a report in reporting_closure\n     ->  people_manager\n4. otherwise  ->  hr_analyst", 15, WHITE)
text(dx + 18, pyy + 196, "most privilege wins", 14, "#b9c8cd")
arrow(dx + dw / 2, top + 70 + 3 * 140 + 112, dx + dw / 2, pyy, VIOLET, label=None)
text(dx + dw / 2 + 12, pyy - 24, "every function asks", 14, SLATE)

# --- E: result
ex, ew = FX + 2070, 370
text(ex, top, "5  Same query, per person", 24, LAVA, font=FONT_HAND)
text(ex, top + 34, "SELECT full_name, base_salary, ssn", 15, SLATE, font=FONT_CODE)
res = [
    ("HR analyst", "Omar Patel", "NULL", "****", 2000),
    ("Anya (manager)", "Omar Patel", "160,975", "****", 46),
    ("ER / Legal", "Omar Patel", "160,975", "175-85-1525", 2000),
]
for i, (who, nm, sal, ssn, rows_) in enumerate(res):
    ry = top + 70 + i * 190
    rect(ex, ry, ew, 160, WHITE, NAVY)
    text(ex + 16, ry + 14, who, 18, LAVA)
    text(ex + 16, ry + 50, f"{nm}  |  {sal}  |  {ssn}", 15, NAVY, font=FONT_CODE)
    text(ex + 16, ry + 110, f"{rows_:,} rows visible", 15, SLATE)
arrow(dx + dw, top + 300, ex, top + 300, NAVY)

# arrows A->B->C
arrow(ax + aw, top + 220, bx, top + 220, NAVY)
arrow(bx + bw, top + 340, cx, top + 340, NAVY)

# inheritance strip
rect(FX + 50, FY + 1060, 2380, 80, GREEN_BG, GREEN, sw=1)
ctext(FX + 50, FY + 1060, 2380, 80,
      "Gold views, the comp metric view, Genie and the People Insights app all read these tables, so they inherit the "
      "same masks and row filter with no policies of their own.", 19, "#006b47")

# ============================================================================ frame 3: one row filter
FX, FY = 4320, 0
frame(FX, FY, 2200, 1180, "3 - One row filter for every table")
heading(FX + 50, FY + 40, "One row filter covers every table",
        "Tag each table's employee key once. A single policy finds those columns, and one lookup decides the rows.")

top = FY + 170
# --- tagged key columns
text(FX + 50, top, "1  Employee key tagged reporting_line", 24, LAVA, font=FONT_HAND)
text(FX + 50, top + 34, "any column name, any schema", 16, SLATE)
keys = [
    ("glb_silver.employees", "employee_id"), ("glb_silver.performance", "employee_id"),
    ("glb_silver.leave_records", "employee_id"), ("glb_silver.employee_relations", "employee_id"),
    ("tr_silver.compensation", "employee_id"), ("ta_silver.requisitions", "hiring_manager_id"),
    ("ta_silver.applications", "hiring_manager_id"), ("lrn_silver.training_records", "employee_id"),
    ("glb_bronze.hris_workers_raw", "worker_id"),
]
kx, kw = FX + 50, 560
for i, (t, c) in enumerate(keys):
    ky = top + 70 + i * 82
    rect(kx, ky, kw, 66, OAT, NAVY2, sw=1)
    text(kx + 16, ky + 10, t, 15, NAVY, font=FONT_CODE)
    text(kx + 16, ky + 36, c, 15, LAVA, font=FONT_CODE)
    rect(kx + kw - 150, ky + 18, 132, 28, LAVA, LAVA, sw=1, rough=0)
    ctext(kx + kw - 150, ky + 18, 132, 28, "reporting_line", 13, WHITE, FONT_CODE)
    arrow(kx + kw, ky + 33, FX + 760, top + 350, LINE)

# --- one policy + function
px, pw = FX + 760, 560
text(px, top, "2  One policy, one function", 24, LAVA, font=FONT_HAND)
rect(px, top + 250, pw, 170, WHITE, LAVA)
text(px + 20, top + 268,
     "hr_demo_reporting_line_row_filter\n  ON CATALOG\n  ROW FILTER rf_reporting_line\n"
     "  MATCH COLUMNS has_tag_value(\n    'hr_scope_demo_tag','reporting_line') AS e\n  USING COLUMNS (e)", 15, NAVY,
     font=FONT_CODE)
rect(px, top + 520, pw, 150, VIOLET_BG, VIOLET)
text(px + 20, top + 538,
     "rf_reporting_line(emp) =\n     current_persona() <> 'people_manager'\n  OR emp IN (SELECT report_id\n"
     "             FROM reporting_closure\n             WHERE manager_id = <you>)", 15, NAVY, font=FONT_CODE)
arrow(px + pw / 2, top + 420, px + pw / 2, top + 520, VIOLET)
text(px, top + 700, "Other personas pass every row; their\nsensitive columns are handled by the masks.", 16, SLATE)

# --- closure
qx = FX + 1420
text(qx, top, "3  Hierarchy flattened once", 24, LAVA, font=FONT_HAND)
text(qx, top + 34, "rebuilt from the HRIS on a schedule", 16, SLATE)
rect(qx, top + 70, 330, 150, OAT, NAVY2, sw=1)
text(qx + 16, top + 84, "HRIS workers (Workday)", 16, NAVY)
text(qx + 16, top + 116, "employee_id | manager_id\nW00075      | W00030\nW00210      | W00075", 14, NAVY, font=FONT_CODE)
arrow(qx + 165, top + 220, qx + 165, top + 280, NAVY, label=None)
text(qx + 180, top + 236, "self-join, every depth", 14, SLATE)
rect(qx, top + 280, 330, 230, WHITE, VIOLET)
text(qx + 16, top + 294, "reporting_closure", 16, NAVY, font=FONT_CODE)
text(qx + 16, top + 326, "manager | report  | depth\nW00030  | W00030  | self\nW00030  | W00075  | 1\n"
     "W00030  | W00210  | 2\n...     | ...     | ...", 14, NAVY, font=FONT_CODE)
text(qx + 16, top + 470, "one row per manager-report pair", 14, SLATE)
arrow(qx, top + 400, px + pw, top + 600, VIOLET, dashed=True, label="one lookup")

# tree
tx0 = qx + 380
text(tx0, top + 70, "Anya's line = 46", 20, NAVY, font=FONT_HAND)
box(tx0 + 90, top + 120, 190, 52, "Anya Nguyen", NAVY, NAVY, 16, WHITE)
for i, nm in enumerate(["Greta Patel", "Omar Patel", "Wei Garcia"]):
    mx = tx0 + i * 130
    box(mx, top + 240, 120, 48, nm, VIOLET_BG, VIOLET, 14)
    arrow(tx0 + 185, top + 172, mx + 60, top + 240, VIOLET)
    box(mx + 5, top + 350, 110, 48, "14 analysts", OAT, NAVY2, 14)
    arrow(mx + 60, top + 288, mx + 60, top + 350, NAVY2)
text(tx0, top + 420, "1 + 3 + 42 = 46 people.\nPriya (her manager), the CEO and\nother departments: 0 rows.", 16, SLATE)

# bottom callout
rect(FX + 50, FY + 1060, 2100, 80, GREEN_BG, GREEN, sw=1)
ctext(FX + 50, FY + 1060, 2100, 80,
      "New table? Tag its employee key reporting_line and it's filtered. No new row filter, no new policy. A reorg "
      "flows in on the next closure rebuild.", 19, "#006b47")

doc = {"type": "excalidraw", "version": 2, "source": "https://excalidraw.com", "elements": elements,
       "appState": {"viewBackgroundColor": "#ffffff", "gridSize": None}, "files": {}}
out = Path(__file__).resolve().parent.parent / "docs" / "abac-design.excalidraw"
out.write_text(json.dumps(doc, indent=1))
print(f"wrote {out} ({len(elements)} elements)")
