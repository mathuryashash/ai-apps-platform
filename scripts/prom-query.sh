#!/usr/bin/env bash
# Query Prometheus HTTP API for RED metrics after a load test run.
set -euo pipefail

PROM="${PROM_URL:-http://localhost:18090}"

query() {
  local label=$1; local q=$2
  echo -n "  $label: "
  curl -sf "${PROM}/api/v1/query?query=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$q")" \
    | python3 -c "
import json,sys
data=json.load(sys.stdin)
results=data.get('data',{}).get('result',[])
if not results:
    print('no data')
else:
    for r in results:
        metric=r.get('metric',{})
        val=r.get('value',[None,None])[1]
        svc=metric.get('service_name',metric.get('job','?'))
        print(f'{svc}={val}')
"
}

echo "==> Prometheus RED metrics query (at $(date -u +%Y-%m-%dT%H:%M:%SZ))"
query "req/s"      "sum(rate(http_server_duration_milliseconds_count[2m])) by (service_name)"
query "5xx rate"   "sum(rate(http_server_duration_milliseconds_count{http_status_code=~'5..'}[2m])) by (service_name)"
query "p50 (ms)"   "histogram_quantile(0.50, sum(rate(http_server_duration_milliseconds_bucket[2m])) by (le, service_name))"
query "p95 (ms)"   "histogram_quantile(0.95, sum(rate(http_server_duration_milliseconds_bucket[2m])) by (le, service_name))"
echo "==> Done."
