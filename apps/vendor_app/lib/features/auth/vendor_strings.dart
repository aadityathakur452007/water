// Vendor auth strings (Hindi-first, English fallback) — mirrors user_app
// authStringsHi precedent. Vendor accounts are admin-created: no guest
// browse, no signup link.

const Map<String, String> vendorStringsHi = {
  'appName': 'Shodasha Vendor',
  'appTagline': 'Delivery partner app',
  'loginTitle': 'Mobile number se login karein',
  'loginSubtitle': 'OTP se verify hoga • vendor account admin banata hai',
  'phoneLabel': 'Mobile number',
  'phoneHint': '93021 90067',
  'phoneError': 'Sahi 10-digit mobile number likhein (6–9 se shuru)',
  'sendOtp': 'OTP bhejein',
  'sending': 'OTP bheja ja raha hai…',
  'otpTitle': 'OTP daalein',
  'otpSentTo': '6-digit OTP bheja gaya:',
  'verify': 'Verify karein',
  'verifying': 'Verify ho raha hai…',
  'resend': 'OTP dobara bhejein',
  'tooManyAttempts': '5 baar galat OTP — naya OTP mangwayein',
  'codeExpired': 'OTP expired ho gaya — naya OTP bhejein',
  'invalidCode': 'Galat OTP — dobara try karein',
  'smsError': 'OTP SMS nahi bheja ja saka — thodi der me retry karein',
  'serverError': 'Server me dikkat — thodi der me retry karein',
  'networkError': 'Network me dikkat — dobara try karein',
  'newDevice': 'Naya device detect hua — purana session surakshit hai',
  'editNumber': 'Number badlein',
  'notVendor': 'Ye number vendor account se juda nahi — admin se sampark karein',
  'demoLogin': 'Demo try karein (bina OTP)',
  'demoTitle': 'Demo login',
  'demoHint': 'Seeded demo account — QA ke liye, bina OTP',
  'demoVendor': 'Demo vendor bharein',
  'demoGo': 'Demo se login karein',
};

String resendInHi(int seconds) => 'Naya OTP $seconds second me milega';
String attemptsHi(int left) => '$left prayas bache (kul 5)';
