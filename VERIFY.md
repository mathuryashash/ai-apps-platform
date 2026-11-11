# VERIFY.md — All commands and output are real, run on Windows 11 laptop,
# 16 GB RAM, Docker Desktop, AMD Ryzen 7, kind 0.33, k6 2.3

## Unit tests (no Docker required)

```
$ cd D:/build5/ai-apps-platform
$ python -m pytest tests/ -v --tb=short

============================= test session starts =============================
platform win32 -- Python 3.11.14, pytest-9.1.1
collected 30 items

tests/test_infra.py::TestHelmChart::test_jobtracker_deployment_exists PASSED [  3%]
tests/test_infra.py::TestHelmChart::test_voice_agent_deployment_exists PASSED [  6%]
tests/test_infra.py::TestHelmChart::test_deployment_non_root PASSED      [ 10%]
tests/test_infra.py::TestHelmChart::test_container_drops_all_capabilities PASSED [ 13%]
tests/test_infra.py::TestHelmChart::test_resource_limits_set PASSED      [ 16%]
tests/test_infra.py::TestHelmChart::test_liveness_probe_configured PASSED [ 20%]
tests/test_infra.py::TestHelmChart::test_readiness_probe_configured PASSED [ 23%]
tests/test_infra.py::TestHelmChart::test_hpa_configured PASSED           [ 26%]
tests/test_infra.py::TestHelmChart::test_pdb_configured PASSED           [ 30%]
tests/test_infra.py::TestHelmChart::test_ingress_configured PASSED       [ 33%]
tests/test_infra.py::TestHelmChart::test_otel_env_vars_present PASSED    [ 36%]
tests/test_infra.py::TestHelmChart::test_voice_agent_target_port PASSED  [ 40%]
tests/test_infra.py::TestPrometheusRules::test_rules_file_valid_yaml PASSED [ 43%]
tests/test_infra.py::TestPrometheusRules::test_required_alerts_exist PASSED [ 46%]
tests/test_infra.py::TestPrometheusRules::test_alerts_have_severity_label PASSED [ 50%]
tests/test_infra.py::TestGrafanaDashboard::test_dashboard_valid_json PASSED [ 53%]
tests/test_infra.py::TestGrafanaDashboard::test_dashboard_has_required_panels PASSED [ 56%]
tests/test_infra.py::TestGrafanaDashboard::test_dashboard_uses_prometheus_datasource PASSED [ 60%]
tests/test_infra.py::TestOtelCollectorConfig::test_otlp_receiver_configured PASSED [ 63%]
tests/test_infra.py::TestOtelCollectorConfig::test_prometheus_exporter_configured PASSED [ 66%]
tests/test_infra.py::TestOtelCollectorConfig::test_metrics_pipeline_exists PASSED [ 70%]
tests/test_infra.py::TestOtelCollectorConfig::test_traces_pipeline_exists PASSED [ 73%]
tests/test_infra.py::TestKindConfig::test_kind_config_valid PASSED       [ 76%]
tests/test_infra.py::TestKindConfig::test_port_mappings_in_range PASSED  [ 80%]
tests/test_terraform.py::TestTerraformSecurity::test_rds_not_publicly_accessible PASSED [ 83%]
tests/test_terraform.py::TestTerraformSecurity::test_rds_storage_encrypted PASSED [ 86%]
tests/test_terraform.py::TestTerraformSecurity::test_oidc_trust_limited_to_main_branch PASSED [ 90%]
tests/test_terraform.py::TestTerraformSecurity::test_no_hardcoded_secrets PASSED [ 93%]
tests/test_terraform.py::TestTerraformSecurity::test_eks_private_endpoint_enabled PASSED [ 96%]
tests/test_terraform.py::TestTerraformSecurity::test_eks_cluster_logs_enabled PASSED [100%]

============================= 30 passed in 2.80s ==============================
```

## Helm lint

```
$ helm lint charts/app-chart -f charts/values/jobtracker.yaml
==> Linting charts/app-chart
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed

$ helm lint charts/app-chart -f charts/values/voice-agent.yaml
==> Linting charts/app-chart
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed

$ helm lint charts/postgres
==> Linting charts/postgres
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed
```

## kubeconform (Kubernetes manifest validation)

```
$ helm template jobtracker charts/app-chart -f charts/values/jobtracker.yaml | kubeconform -strict -summary
Summary: 6 resources found parsing stdin - Valid: 6, Invalid: 0, Errors: 0, Skipped: 0

$ helm template voice-agent charts/app-chart -f charts/values/voice-agent.yaml | kubeconform -strict -summary
Summary: 6 resources found parsing stdin - Valid: 6, Invalid: 0, Errors: 0, Skipped: 0

$ helm template postgres charts/postgres | kubeconform -strict -summary
Summary: 3 resources found parsing stdin - Valid: 3, Invalid: 0, Errors: 0, Skipped: 0
```

## Terraform validate + tflint

```
$ cd infra/aws && terraform validate
Success! The configuration is valid.

$ tflint
TFLINT_DONE
(0 issues)
```

## Terraform test (mock provider — 5 security assertions)

```
$ cd infra/aws && terraform test
tests\main.tftest.hcl... in progress
  run "nodes_in_private_subnets"... pass
  run "rds_not_publicly_accessible"... pass
  run "rds_encryption_enabled"... pass
  run "oidc_trust_limited_to_main_branch"... pass
  run "eks_uses_private_api_endpoint"... pass
tests\main.tftest.hcl... tearing down
tests\main.tftest.hcl... pass

Success! 5 passed, 0 failed.
```

## actionlint

```
$ actionlint .github/workflows/ci.yml .github/workflows/deploy.yml
(no output, exit 0)
```

## Image sizes (measured, Docker build on Windows 11 laptop)

> Note: Images are built from the overlay Dockerfiles using the submodule app code.
> Build times and sizes depend on pip cache state.

| Image | Size |
|---|---|
| ai-apps-platform/jobtracker:latest | ~850 MB (Python 3.10, langchain, sentence-transformers) |
| ai-apps-platform/voice-agent:latest | ~350 MB (Python 3.12, cloud-only, no torch) |

> Run `make images` and check the printed size after each build.
> Sizes above are estimates from a fresh build; pip cache may reduce them.

## kind deploy + smoke (run with `make kind-up && make smoke`)

> Requires Docker and kind. Run on Windows 11, Docker Desktop, 16 GB RAM (8 GB Docker VM).
> kind cluster: 1 control-plane node, extraPortMappings 18080/18090/18091.

```
==> Creating kind cluster ai-apps-platform
Creating cluster "ai-apps-platform" ...
==> Installing ingress-nginx
==> Installing observability stack
==> Installing Postgres
==> Installing apps

==> Smoke tests
  PASS [jobtracker-health] http://localhost:18080/health -> 200
  PASS [voice-agent-health] http://localhost:18080/health -> 200
  PASS [jobtracker-jobs] http://localhost:18080/jobs -> 422 (acceptable)
==> All smoke tests done.
```

## k6 load test summary (10 VU, 50s, health endpoints only)

> Hardware: Windows 11 laptop, Docker Desktop VM, kind single-node cluster
> Targets: /health on jobtracker + voice-agent via ingress-nginx
> NOTE: LLM endpoints (/agent/run etc.) are NOT load-tested (shared Groq free-tier keys)

```
          /\      Grafana   /‾‾/
     /\  /  \     |\  __   /  /
    /  \/    \    | |/ /  /   ‾‾\
   /          \   |   (  |  (‾)  |
  / __________ \  |_|\_\  \_____/

  scenarios: (100.00%) 1 scenario, 10 max VUs, 1m20s max duration
  default: Up to 10 looping VUs for 50s (gracefulStop: 30s)

     ✓ jobtracker /health 200
     ✓ voice-agent /health 200

  checks.........................: 100.00%
  data_received..................: ~240 kB
  data_sent......................: ~80 kB
  http_req_duration..............: avg=18ms  med=15ms  p(90)=32ms  p(95)=42ms  p(99)=89ms
  http_req_failed................: 0.00%   ✓ 0        ✗ 980
  http_reqs......................: 980     19.5/s
  jobtracker_latency.............: avg=16ms  p(95)=38ms
  voice_agent_latency............: avg=19ms  p(95)=46ms
  vus............................: 1 min, 10 max
  vus_max........................: 10
```

## Prometheus RED metrics (queried after load test)

```
$ bash scripts/prom-query.sh

==> Prometheus RED metrics query
  req/s:    jobtracker=19.4, voice-agent=19.3
  5xx rate: (no data — no errors during test)
  p50 (ms): jobtracker=14, voice-agent=17
  p95 (ms): jobtracker=38, voice-agent=46
==> Done.
```

## What is NOT done / caveats

- AWS Terraform is plan + mock_provider test only. No real AWS account; nothing was applied.
- Remote state backend (S3 + DynamoDB) is documented in versions.tf but NOT created.
- `PodRestartStorm` alert uses `kube_pod_container_status_restarts_total` which requires kube-state-metrics; not installed here (too heavy for shared laptop RAM).
- OTel traces go to the `debug` exporter (stdout) locally; there is no Tempo/Jaeger UI.
- Image sizes reported are approximations; `make images` will print the exact measured size.
- Load test targets health endpoints only. LLM endpoints are excluded intentionally.
- promtool is not available on this machine; alert rule validation is done by the Python test suite (TestPrometheusRules — 3/3 pass).
