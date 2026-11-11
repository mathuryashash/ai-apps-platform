/**
 * k6 load test for AI Apps Platform — health + non-LLM endpoints only.
 * Run: k6 run loadtest/k6-health.js
 * Targets the ingress-nginx on localhost:18080 (kind extraPortMapping).
 *
 * Why only non-LLM: shared Groq free-tier keys; load-testing LLM endpoints
 * would exhaust rate limits and produce meaningless latency numbers.
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const errorRate = new Rate('errors');
const jobtrackerLatency = new Trend('jobtracker_latency', true);
const voiceLatency = new Trend('voice_agent_latency', true);

export const options = {
  stages: [
    { duration: '10s', target: 5 },   // ramp up
    { duration: '30s', target: 10 },  // sustained load
    { duration: '10s', target: 0 },   // ramp down
  ],
  thresholds: {
    http_req_failed: ['rate<0.05'],      // <5% errors
    http_req_duration: ['p(95)<3000'],   // p95 <3s (health endpoints are fast)
    errors: ['rate<0.05'],
  },
};

const INGRESS = __ENV.INGRESS_URL || 'http://localhost:18080';

export default function () {
  // jobtracker health
  const jRes = http.get(`${INGRESS}/health`, {
    headers: { Host: 'jobtracker.local' },
    timeout: '10s',
  });
  check(jRes, {
    'jobtracker /health 200': (r) => r.status === 200,
  });
  errorRate.add(jRes.status !== 200);
  jobtrackerLatency.add(jRes.timings.duration);

  // voice-agent health
  const vRes = http.get(`${INGRESS}/health`, {
    headers: { Host: 'voice-agent.local' },
    timeout: '10s',
  });
  check(vRes, {
    'voice-agent /health 200': (r) => r.status === 200,
  });
  errorRate.add(vRes.status !== 200);
  voiceLatency.add(vRes.timings.duration);

  sleep(0.5);
}
