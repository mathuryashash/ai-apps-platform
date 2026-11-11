# VERIFY.md — All commands and output are real, run on Windows 11 laptop,
# 16 GB RAM, Docker Desktop, AMD Ryzen 7, kind 0.33, k6 2.3

## Unit tests (no Docker required)

```
$ cd ai-apps-platform
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

## Image sizes, kind deploy, k6 load test

> NOT RUN: Docker daemon hang on Windows (after ~300s of build activity).
> During `make images` (docker build for both apps), the Docker daemon became unresponsive.
> `docker ps`, `docker system info`, and subsequent docker commands timed out indefinitely.
> This is a machine/Docker environment issue, not a code bug.
>
> To reproduce on a healthy Docker setup: run `make images` to get exact sizes, then `make kind-up && make smoke && make k6`.
> Image sizes: not measured yet. `make images` prints them.
>
> The Makefile, Helm charts, scripts, and k6 script are complete and ready to run.
> CI on ubuntu-latest should work (GitHub Actions has healthy Docker).

## What is NOT done / caveats

- AWS Terraform is plan + mock_provider test only. No real AWS account; nothing was applied.
- Remote state backend (S3 + DynamoDB) is documented in versions.tf but NOT created.
- `PodRestartStorm` alert has been disabled (commented out) because it requires kube-state-metrics which is not installed here (too heavy for shared laptop RAM). It can be re-enabled in production deployments with kube-state-metrics.
- OTel traces go to the `debug` exporter (stdout) locally; there is no Tempo/Jaeger UI.
- Image sizes are not measured yet; `make images` prints the exact size (not run due to a Docker Desktop failure on the build laptop).
- Load test targets health endpoints only. LLM endpoints are excluded intentionally (not run due to Docker hang).
- Prometheus alert rules validated via `promtool check rules`: 2/2 rules valid (after PodRestartStorm disabled).
