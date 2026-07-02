import http from 'k6/http';
import { check, sleep } from 'k6';

// Read target URL from environment or fallback to localhost
const TARGET_URL = __ENV.TARGET_URL || 'http://localhost:8000';

export const options = {
  stages: [
    { duration: '30s', target: 10 }, // Stage 1: Warmup - ramp up to 10 users
    { duration: '1m', target: 50 },  // Stage 2: Main Load - sustain 50 users
    { duration: '30s', target: 100 }, // Stage 3: Stress Spike - sudden jump to 100 users
    { duration: '30s', target: 0 },   // Stage 4: Cooldown - ramp down to 0 users
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],  // Error rate must be less than 1%
    http_req_duration: ['p(95)<500'], // 95% of requests must complete under 500ms
  },
};

export default function () {
  // 1. Visit HTML Dashboard (static render + system metrics querying)
  const dashboardRes = http.get(TARGET_URL);
  check(dashboardRes, {
    'Dashboard status is 200': (r) => r.status === 200,
    'Dashboard contains header': (r) => r.body.includes('CloudOps Live Dashboard'),
  });
  sleep(1);

  // 2. Query Health Check API (lightweight endpoint)
  const healthRes = http.get(`${TARGET_URL}/api/v1/health`);
  check(healthRes, {
    'Health check status is 200': (r) => r.status === 200,
    'App is healthy': (r) => JSON.parse(r.body).status === 'healthy',
  });
  sleep(0.5);

  // 3. Query Database items list (simulating DB read operation)
  const itemsRes = http.get(`${TARGET_URL}/api/v1/items`);
  check(itemsRes, {
    'Items list status is 200': (r) => r.status === 200,
    'Items array retrieved': (r) => Array.isArray(JSON.parse(r.body)),
  });
  sleep(1);

  // 4. Create new DB items (simulating write load)
  const payload = JSON.stringify({
    name: `LoadTest-Item-${__VU}-${__ITER}`,
    description: 'Generated dynamically during k6 execution',
    price: Math.random() * 100
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  const createRes = http.post(`${TARGET_URL}/api/v1/items`, payload, params);
  check(createRes, {
    'Create item status is 201': (r) => r.status === 201,
    'Item created returns JSON': (r) => JSON.parse(r.body).id !== undefined,
  });
  sleep(2);

  // 5. Query system metrics (metrics scrape simulation)
  const metricsRes = http.get(`${TARGET_URL}/metrics`);
  check(metricsRes, {
    'Metrics status is 200': (r) => r.status === 200,
  });
  sleep(1);
}
