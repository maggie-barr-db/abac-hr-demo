# abac-hr-demo

A Databricks demo of attribute-based access control (ABAC) for HR data, built on synthetic data.

It shows how one governed tag (`hr_pii_demo_tag`) with four sensitivity levels protects HR data across multiple Unity Catalog catalogs, so that each persona (HR analyst, department head, HR trusted, ER/Legal) sees exactly the tiers and rows they should. It then pressure-tests that model through Genie, Genie Code, metric views, data copies, and a Databricks App running on behalf of the user.

All data in this repo is synthetic.

Status: in design. Code to follow.
