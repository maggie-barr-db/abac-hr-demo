# abac-hr-demo

A Databricks demo of attribute-based access control (ABAC) for HR data, built on synthetic data.

It shows how one governed tag (`hr_pii_demo_tag`) with four sensitivity levels protects HR data across multiple Unity Catalog catalogs, so that each persona (HR analyst, department head, HR trusted, ER/Legal) sees exactly the tiers and rows they should. It then pressure-tests that model through Genie, Genie Code, metric views, data copies, and a Databricks App running on behalf of the user.

All data in this repo is synthetic.

Status: in design. Code to follow.

## People Insights app

`app/` is a Databricks App (React UI + FastAPI) that runs entirely on behalf of the signed-in user, with user authorization scopes `sql` and `dashboards.genie`.

- **Screens:** Overview, Directory (with a profile drawer grouped by sensitivity tier), My Team (people managers), Compensation (HR trusted and ER/Legal), Ask AI (the Genie Conversation API, also available as a side panel on every screen), and My Access.
- **Persona gating:** tabs are shown or hidden by `glb_governance.current_persona()`. That's presentation only. Opening a hidden page by URL still works, and Unity Catalog masks or filters what comes back.
- **Demo persona switch:** the menu under the user name writes to the demo-only `persona_override` table.
- **Deploy:** `scripts/deploy_app.sh <profile>` builds the UI and deploys the app. To run locally, set `LOCAL_DEV_PROFILE=<profile>` and run `uvicorn backend.main:app` from `app/`, plus `npm run dev` in `app/frontend`.
