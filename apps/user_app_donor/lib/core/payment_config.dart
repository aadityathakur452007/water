// Publishable Razorpay test key (public by design — the secret stays
// server-side in workers/api/.env). Empty = UPI gateway disabled with an
// honest message; COD keeps working. Set at build time:
//   --dart-define=RAZORPAY_KEY_ID=rzp_test_...
const String kRazorpayKeyId = String.fromEnvironment(
  'RAZORPAY_KEY_ID',
  defaultValue: '',
);
