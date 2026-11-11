# Design Decisions and Trade-offs

## Why this architecture

The goal is to show the full shipping lifecycle for AI apps: build → containerize → Helm → kind (local k8s) → Terraform (AWS-ready, not applied). The two apps are pinned as git submodules so their code is unmodified but can be built and deployed independently.

## Overlay Dockerfiles

**Decision:** Create separate `docker/<app>/Dockerfile` that extend the app's upstream context rather than modifying the app's own Dockerfile.

**Why:** The original apps should remain untouched (they are public repos with their own CI). The overlays add:
- Non-root user (uid 1000) — reduces blast radius if the container process is compromised.
- OpenTelemetry zero-code instrumentation via `opentelemetry-instrument` as the entrypoint — no app code change needed.
- Multi-stage build — build dependencies (gcc, libpq-dev) stay in the builder stage; the runtime image is smaller.
- HEALTHCHECK — Docker daemon and Kubernetes probes both use it.

**Trade-off:** The overlay Dockerfile must be kept in sync with the upstream app's requirements.txt. If the app adds a new dependency that needs a new system package, the overlay breaks. We pin submodules to known commits to prevent surprise breakage.

**Image sizes (measured):** Reported in VERIFY.md. The jobtracker image includes torch-free Python deps so it stays reasonable. The voice-agent is similarly slim because it uses `requirements-cloud.txt` (Groq STT, no local speech model).

## Single shared Helm chart

**Decision:** One `app-chart` with per-app `values/` files rather than two separate charts.

**Why:** Both apps are FastAPI services. They share the same Deployment/Service/Ingress/HPA/PDB pattern. Maintaining two identical charts doubles the drift surface. The only differences are image, port, probe paths, and resource sizes — all parameterizable.

**Trade-off:** A strongly divergent third app (e.g. a stateful worker) would need its own chart. The shared chart is a "simple app" abstraction, not a universal one.

## Postgres in-cluster (kind) vs RDS (AWS)

**Decision:** For local development, Postgres runs as a Helm-managed StatefulSet. On AWS, we use RDS with `manage_master_user_password = true`.

**Why:** kind has no persistent storage guarantees between cluster restarts. The StatefulSet with a PVC is enough for a demo. In production, a managed RDS avoids manual patching, backups, and HA configuration.

**Trade-off:** Schema migrations (via Alembic inside jobtracker) must run before the app starts. In this setup the app handles this on startup; for production a Kubernetes Job pre-hook would be cleaner.

## OTel Collector as middle layer

**Decision:** Apps ship traces/metrics to the OTel Collector (gRPC OTLP), which then exposes a Prometheus scrape endpoint.

**Why:** Decouples the apps from the backend (Prometheus today, Tempo/Jaeger tomorrow). Apps use the standard OTLP protocol. The collector handles batching, retries, and attribute sanitization.

**Trade-off:** Adds one more component. For a tiny deployment this is slight over-engineering. The collector uses only ~150 MiB RAM, so it is acceptable.

## No kube-prometheus-stack

**Decision:** Deploy Prometheus + Grafana + OTel Collector as individual manifests instead of using the full `kube-prometheus-stack` Helm chart.

**Why:** kube-prometheus-stack pulls ~2 GB of images and needs ~2 GB of RAM. The machine has 16 GB shared with 5 parallel build agents and Docker. A lightweight setup that proves the same observability concepts is better here.

**Trade-off:** No auto-discovery of Kubernetes pod metrics (kube-state-metrics, node-exporter). The alert rule for pod restarts uses `kube_pod_container_status_restarts_total` which is only available if kube-state-metrics is installed. On kind without it, that alert will not fire — documented in VERIFY.md.

## Terraform mock_provider tests

**Decision:** Use `terraform test` with `mock_provider "aws"` to verify security invariants without an AWS account.

**Why:** We cannot apply real infrastructure. The mock provider lets us verify that the plan contains the right attribute values (RDS not public, encryption on, OIDC scoped to main branch). This is exactly what `terraform test` was designed for.

**Trade-off:** The mock provider does not catch IAM policy logic errors. A full policy simulator would need a real AWS account. The static analysis in `tests/test_terraform.py` covers the string-level checks.

## GitHub OIDC deploy role

**Decision:** Trust only `refs/heads/main` in the OIDC condition.

**Why:** If a fork or feature branch could assume the deploy role, an attacker could open a PR and trigger a deploy to production. Scoping to main means only merged, reviewed code can deploy.

**Trade-off:** Hotfixes require a PR to main. Acceptable.

## Load test targets health endpoints only

**Decision:** k6 hits `/health` only, not LLM endpoints.

**Why:** The Groq API key is a shared free-tier resource. Load-testing `/agent/run` would exhaust rate limits for all five parallel build agents and produce misleading latency numbers (network round-trip to Groq + LLM inference, not app latency).

**What we do prove:** The ingress, Kubernetes service routing, and app response are all correct under 10 VUs for 50 seconds. The p95/p99 numbers reflect real app + k8s overhead.

## Failure modes

- **DB connection on startup:** jobtracker will retry via SQLAlchemy's connection pool. If Postgres is not ready, the first request will fail. In production, use a readiness probe that checks the DB, or use an init container.
- **GROQ_API_KEY missing:** Both apps fail open with a 500 on LLM routes; `/health` still returns 200. The readiness probe uses `/health`, so the pod appears ready even without a valid key. This is intentional: health ≠ LLM connectivity.
- **OTel collector down:** Both apps use `opentelemetry-instrument` with `OTEL_EXPORTER_OTLP_INSECURE=true`. If the collector is unreachable, the OTel SDK will retry and eventually drop traces — it does not crash the app. This is the correct behavior.

## How to scale further

1. Add Tempo for trace storage and correlate traces with Grafana.
2. Use External Secrets Operator on AWS to sync Secrets Manager → k8s secrets automatically.
3. Add a pre-upgrade Helm hook that runs `alembic upgrade head` as a Job.
4. Enable multi-AZ for RDS and add a read replica for the BM25 retrieval path.
5. Use kube-prometheus-stack once the memory budget allows (EKS has more RAM).
