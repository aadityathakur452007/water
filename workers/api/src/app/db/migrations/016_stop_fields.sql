-- 016_stop_fields.sql — vendor stop field completion (Phase 3 §3.2).
--
-- stops.items_json: SKU/qty snapshot minted at dispatch (assign/reassign),
-- so the vendor sheet renders what was promised even if the catalog moves.
-- orders.instructions: nullable free-text delivery note, user-editable
-- pre-dispatch via PATCH /orders/{id}/instructions (≤500 chars).
-- Both nullable (backfill NULL = absent); code tolerates pre-016 DBs
-- (PRAGMA-gated reads). Apply-once ALTERs like 011/014/015.

ALTER TABLE stops ADD COLUMN items_json TEXT;
ALTER TABLE orders ADD COLUMN instructions TEXT NOT NULL DEFAULT '';
