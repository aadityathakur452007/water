-- 010_config_audit.sql — create config + audit_log on D1 (ADR-054 hotfix).
-- These two slice-1 tables were only ever created by db.init_schema(), which
-- runs on local sqlite but never ran on the prod D1 database — every
-- ConfigRepo.get / admin config route 500'd with "no such table: config"
-- (first seen live on POST /v1/auth/demo, 2026-10-02).
-- Idempotent (IF NOT EXISTS) and shape-identical to app/db.py _SCHEMA.

CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    effective_from TEXT,
    updated_by TEXT,
    updated_at TEXT
);

CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    actor TEXT,
    action TEXT,
    entity TEXT,
    entity_id TEXT,
    trace_id TEXT,
    created_at TEXT
);
