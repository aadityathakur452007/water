-- 032_order_delivery_otp.sql — orders.delivery_otp so customers get OTP immediately on placement.
ALTER TABLE orders ADD COLUMN delivery_otp TEXT;
