import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import { CONFIG } from '../config.js';

// Surface-specific latency & success metrics
const customerLatency = new Trend('ecosystem_customer_latency', true);
const vendorLatency = new Trend('ecosystem_vendor_latency', true);
const adminLatency = new Trend('ecosystem_admin_latency', true);

const customerSuccess = new Rate('ecosystem_customer_success');
const vendorSuccess = new Rate('ecosystem_vendor_success');
const adminSuccess = new Rate('ecosystem_admin_success');

const ecosystemRequests = new Counter('ecosystem_requests_total');

export const options = {
  scenarios: {
    // 1. Customer mobile app traffic (50 VUs)
    customers: {
      executor: 'ramping-vus',
      startVUs: 5,
      stages: [
        { duration: '15s', target: 20 },
        { duration: '30s', target: 50 },
        { duration: '15s', target: 0 },
      ],
      exec: 'customerJourney',
    },
    // 2. Vendor & Rider operations traffic (30 VUs)
    vendors: {
      executor: 'ramping-vus',
      startVUs: 5,
      stages: [
        { duration: '15s', target: 15 },
        { duration: '30s', target: 30 },
        { duration: '15s', target: 0 },
      ],
      exec: 'vendorJourney',
    },
    // 3. Super Admin web portal traffic (20 VUs)
    admins: {
      executor: 'ramping-vus',
      startVUs: 2,
      stages: [
        { duration: '15s', target: 10 },
        { duration: '30s', target: 20 },
        { duration: '15s', target: 0 },
      ],
      exec: 'adminJourney',
    },
  },
  thresholds: {
    'http_req_duration': ['p(95)<2500'],
    'ecosystem_customer_success': ['rate>0.90'],
    'ecosystem_vendor_success': ['rate>0.90'],
    'ecosystem_admin_success': ['rate>0.90'],
  },
};

export function customerJourney() {
  const headers = {
    'Authorization': `Bearer ${CONFIG.CUSTOMER_TOKEN}`,
    'Accept': 'application/json',
  };

  // 1. Browse catalog
  const res1 = http.get(`${CONFIG.CUSTOMER_URL}/v1/catalog`);
  customerLatency.add(res1.timings.duration);
  customerSuccess.add(res1.status === 200);
  ecosystemRequests.add(1);

  // 2. Check my orders
  const res2 = http.get(`${CONFIG.CUSTOMER_URL}/v1/orders`, { headers });
  customerLatency.add(res2.timings.duration);
  customerSuccess.add(res2.status === 200);
  ecosystemRequests.add(1);

  sleep(0.5);
}

export function vendorJourney() {
  const vHeaders = {
    'Authorization': `Bearer ${CONFIG.VENDOR_TOKEN}`,
    'Accept': 'application/json',
  };
  const rHeaders = {
    'Authorization': `Bearer ${CONFIG.RIDER_TOKEN}`,
    'Accept': 'application/json',
  };

  // 1. Vendor inspects placed orders
  const res1 = http.get(`${CONFIG.OPS_URL}/v1/vendor/placed`, { headers: vHeaders });
  vendorLatency.add(res1.timings.duration);
  vendorSuccess.add(res1.status === 200);
  ecosystemRequests.add(1);

  // 2. Rider inspects routes
  const res2 = http.get(`${CONFIG.OPS_URL}/v1/rider/routes/today`, { headers: rHeaders });
  vendorLatency.add(res2.timings.duration);
  vendorSuccess.add(res2.status === 200);
  ecosystemRequests.add(1);

  sleep(0.5);
}

export function adminJourney() {
  const headers = {
    'Authorization': `Bearer ${CONFIG.ADMIN_TOKEN}`,
    'Accept': 'application/json',
  };

  // 1. Admin monitors live vendors
  const res1 = http.get(`${CONFIG.ADMIN_URL}/v1/admin/vendors`, { headers });
  adminLatency.add(res1.timings.duration);
  adminSuccess.add(res1.status === 200);
  ecosystemRequests.add(1);

  // 2. Admin monitors active zones
  const res2 = http.get(`${CONFIG.ADMIN_URL}/v1/admin/zones`, { headers });
  adminLatency.add(res2.timings.duration);
  adminSuccess.add(res2.status === 200);
  ecosystemRequests.add(1);

  sleep(0.5);
}
