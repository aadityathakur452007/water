-- 021_return_upi.sql — returns.upi_id for direct UPI security deposit repayments.
--
-- Adds upi_id to returns table so customers leaving service can directly receive
-- their deposit refund back into their UPI account.
-- Default '' ensures backwards compatibility with existing rows.

ALTER TABLE returns ADD COLUMN upi_id TEXT NOT NULL DEFAULT '';
