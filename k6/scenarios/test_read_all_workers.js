import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import { CONFIG } from '../config.js';

// Custom metrics for each Worker surface
const customerDuration = new Trend('customer_read_duration', true);
const opsDuration = new Trend('ops_read_duration', true);
const adminDuration = new Trend('admin_read_duration', true);

const customerSuccess = new Rate('customer_success_rate');
const opsSuccess = new Rate('ops_success_rate');
const adminSuccess = new Rate('admin_success_rate');

const totalRequests = new Counter('total_read_requests');

export const options = {
  stages: [
    { duration: '15s', target: 10 },  // Ramp up to 10 VUs
    { duration: '20s', target: 30 },  // Ramp up to 30 VUs
    { duration: '25s', target: 50 },  // Ramp up to 50 VUs
    { duration: '30s', target: 100 }, // Peak at 100 VUs
    { duration: '10s', target: 0 },   // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(95)<1500'], // 95% of requests should be below 1.5s
    'customer_success_rate': ['rate>0.95'],
    'ops_success_rate': ['rate>0.95'],
    'admin_success_rate': ['rate>0.95'],
  },
};

export default function () {
  const customerHeaders = {
    'Authorization': `Bearer ${CONFIG.CUSTOMER_TOKEN}`,
    'Accept': 'application/json',
  };

  const vendorHeaders = {
    'Authorization': `Bearer ${CONFIG.VENDOR_TOKEN}`,
    'Accept': 'application/json',
  };

  const riderHeaders = {
    'Authorization': `Bearer ${CONFIG.RIDER_TOKEN}`,
    'Accept': 'application/json',
  };

  const adminHeaders = {
    'Authorization': `Bearer ${CONFIG.ADMIN_TOKEN}`,
    'Accept': 'application/json',
  };

  // 1. Customer Worker Read Queries
  const catalogRes = http.get(`${CONFIG.CUSTOMER_URL}/v1/catalog`);
  customerDuration.add(catalogRes.timings.duration);
  const catOk = check(catalogRes, {
    'catalog status 200': (r) => r.status === 200,
  });
  customerSuccess.add(catOk);
  totalRequests.add(1);

  const ordersRes = http.get(`${CONFIG.CUSTOMER_URL}/v1/orders`, { headers: customerHeaders });
  customerDuration.add(ordersRes.timings.duration);
  const ordOk = check(ordersRes, {
    'customer orders status 200': (r) => r.status === 200,
  });
  customerSuccess.add(ordOk);
  totalRequests.add(1);

  // 2. Vendor / Ops Worker Read Queries
  const placedRes = http.get(`${CONFIG.OPS_URL}/v1/vendor/placed`, { headers: vendorHeaders });
  opsDuration.add(placedRes.timings.duration);
  const placedOk = check(placedRes, {
    'vendor placed status 200': (r) => r.status === 200,
  });
  opsSuccess.add(placedOk);
  totalRequests.add(1);

  const riderRouteRes = http.get(`${CONFIG.OPS_URL}/v1/rider/routes/today`, { headers: riderHeaders });
  opsDuration.add(riderRouteRes.timings.duration);
  const routeOk = check(riderRouteRes, {
    'rider route status 200': (r) => r.status === 200,
  });
  opsSuccess.add(routeOk);
  totalRequests.add(1);

  // 3. Admin Worker Read Queries
  const adminUsersRes = http.get(`${CONFIG.ADMIN_URL}/v1/admin/users`, { headers: adminHeaders });
  adminDuration.add(adminUsersRes.timings.duration);
  const usrOk = check(adminUsersRes, {
    'admin users status 200': (r) => r.status === 200,
  });
  adminSuccess.add(usrOk);
  totalRequests.add(1);

  const adminVendorsRes = http.get(`${CONFIG.ADMIN_URL}/v1/admin/vendors`, { headers: adminHeaders });
  adminDuration.add(adminVendorsRes.timings.duration);
  const venOk = check(adminVendorsRes, {
    'admin vendors status 200': (r) => r.status === 200,
  });
  adminSuccess.add(venOk);
  totalRequests.add(1);

  const adminZonesRes = http.get(`${CONFIG.ADMIN_URL}/v1/admin/zones`, { headers: adminHeaders });
  adminDuration.add(adminZonesRes.timings.duration);
  const zonOk = check(adminZonesRes, {
    'admin zones status 200': (r) => r.status === 200,
  });
  adminSuccess.add(zonOk);
  totalRequests.add(1);

  sleep(0.5); // 500ms pacing between iterations per VU
}
