import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import { CONFIG } from '../config.js';

// Custom metrics for write operations
const customerWriteDuration = new Trend('customer_write_duration', true);
const opsWriteDuration = new Trend('ops_write_duration', true);
const adminWriteDuration = new Trend('admin_write_duration', true);

const customerWriteSuccess = new Rate('customer_write_success');
const opsWriteSuccess = new Rate('ops_write_success');
const adminWriteSuccess = new Rate('admin_write_success');

const ordersCreated = new Counter('orders_created_total');
const writesTotal = new Counter('writes_total');

export const options = {
  stages: [
    { duration: '15s', target: 5 },   // Ramp up to 5 write VUs
    { duration: '20s', target: 15 },  // Ramp up to 15 write VUs
    { duration: '25s', target: 30 },  // Ramp up to 30 write VUs
    { duration: '20s', target: 50 },  // 50 write VUs
    { duration: '10s', target: 0 },   // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(95)<3000'],
    'customer_write_success': ['rate>0.90'],
    'ops_write_success': ['rate>0.90'],
    'admin_write_success': ['rate>0.90'],
  },
};

function uuidv4() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

export default function () {
  const customerHeaders = {
    'Authorization': `Bearer ${CONFIG.CUSTOMER_TOKEN}`,
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  const vendorHeaders = {
    'Authorization': `Bearer ${CONFIG.VENDOR_TOKEN}`,
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  const adminHeaders = {
    'Authorization': `Bearer ${CONFIG.ADMIN_TOKEN}`,
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // 1. Customer Worker Write Flow: Quote -> Place Order
  const quotePayload = JSON.stringify({
    items: [{ sku: 'refill', qty: 1 }],
    e: 0,
    address_id: CONFIG.ADDRESS_ID,
    window_start: '2026-11-25T07:00:00Z',
  });

  const quoteRes = http.post(`${CONFIG.CUSTOMER_URL}/v1/quotes`, quotePayload, { headers: customerHeaders });
  
  if (quoteRes.status === 200) {
    const quoteData = JSON.parse(quoteRes.body);
    const orderHeaders = Object.assign({}, customerHeaders, {
      'Idempotency-Key': uuidv4(),
    });

    const orderPayload = JSON.stringify({
      items: [{ sku: 'refill', qty: 1 }],
      e: 0,
      address_id: CONFIG.ADDRESS_ID,
      window_start: '2026-11-25T07:00:00Z',
      quote_hash: quoteData.quote_hash,
      quote_total: quoteData.total,
      quote_rate_version: 'v1',
      quote_expires_at: quoteData.expires_at,
      payment_mode: 'cod',
    });

    const orderRes = http.post(`${CONFIG.CUSTOMER_URL}/v1/orders`, orderPayload, { headers: orderHeaders });
    customerWriteDuration.add(orderRes.timings.duration);
    const ordOk = check(orderRes, {
      'order created status 201': (r) => r.status === 201,
    });
    customerWriteSuccess.add(ordOk);
    if (ordOk) ordersCreated.add(1);
    writesTotal.add(1);
  } else {
    customerWriteSuccess.add(false);
  }

  // 2. Vendor / Ops Worker Write: Duty Toggle
  const dutyPayload = JSON.stringify({ on: true });
  const dutyRes = http.post(`${CONFIG.OPS_URL}/v1/vendor/duty`, dutyPayload, { headers: vendorHeaders });
  opsWriteDuration.add(dutyRes.timings.duration);
  const dutyOk = check(dutyRes, {
    'vendor duty write status 200': (r) => r.status === 200,
  });
  opsWriteSuccess.add(dutyOk);
  writesTotal.add(1);

  // 3. Admin Worker Write: Issue / Rotate Access Code
  const codePayload = JSON.stringify({ ttl_days: 90 });
  const codeRes = http.post(
    `${CONFIG.ADMIN_URL}/v1/admin/users/${CONFIG.VENDOR_USER_ID}/access-codes`,
    codePayload,
    { headers: adminHeaders }
  );
  adminWriteDuration.add(codeRes.timings.duration);
  const codeOk = check(codeRes, {
    'admin issue code status 200 or 201': (r) => r.status === 200 || r.status === 201,
  });
  adminWriteSuccess.add(codeOk);
  writesTotal.add(1);

  sleep(1.0); // 1s pause between write bursts per VU
}
