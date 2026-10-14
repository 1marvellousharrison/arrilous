-- Spec 16/17 v2 — a provider decides how long today's shift is when going
-- active. The planned hours are kept so the Active page can show the plan and
-- let the provider re-plan, extend or trim it while the shift runs.
ALTER TABLE logistics_organizations ADD COLUMN planned_hours REAL;
ALTER TABLE logistics_riders ADD COLUMN planned_hours REAL;