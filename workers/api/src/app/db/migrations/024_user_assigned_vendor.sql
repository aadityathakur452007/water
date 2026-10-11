-- 024_user_assigned_vendor.sql — users.assigned_vendor_id for trusted vendor auto-routing.
--
-- When an admin assigns an order to a vendor, that vendor becomes the customer's
-- trusted/preferred vendor. Subsequent orders for this customer automatically route
-- to this trusted partner if active and serving the zone, eliminating repetitive admin clicks.

ALTER TABLE users ADD COLUMN assigned_vendor_id TEXT;
