SHELL := /bin/bash
.ONESHELL:
MAKEFLAGS += --no-print-directory

CLUSTER_NAME   := ai-apps-platform
SLUG           := ai-apps-platform
IMAGE_JOBTRACK := $(SLUG)/jobtracker:latest
IMAGE_VOICE    := $(SLUG)/voice-agent:latest
NAMESPACE      := default
KUBECONFIG_ENV := KUBECONFIG=$(HOME)/.kube/config

# Prometheus NodePort service (provisioned in kind-up)
PROM_URL       := http://localhost:18090

.PHONY: all lint test kind-up kind-down smoke bench k6 helm-lint \
        terraform-lint terraform-test images build-jobtracker build-voice clean

all: lint test

## ── Lint ────────────────────────────────────────────────────────────────────
lint: helm-lint kubeconform-check terraform-lint promtool-check actionlint-check
	@echo "All lint checks passed."

helm-lint:
	helm lint charts/app-chart -f charts/values/jobtracker.yaml
	helm lint charts/app-chart -f charts/values/voice-agent.yaml
	helm lint charts/postgres

kubeconform-check:
	helm template jobtracker charts/app-chart -f charts/values/jobtracker.yaml \
	  | kubeconform -strict -summary -schema-location default
	helm template voice-agent charts/app-chart -f charts/values/voice-agent.yaml \
	  | kubeconform -strict -summary -schema-location default
	helm template postgres charts/postgres \
	  | kubeconform -strict -summary -schema-location default

terraform-lint:
	cd infra/aws && terraform fmt -check && terraform validate
	cd infra/aws && tflint --init && tflint

terraform-test:
	cd infra/aws && terraform test

promtool-check:
	promtool check rules observability/rules/app-alerts.yml

actionlint-check:
	actionlint .github/workflows/ci.yml .github/workflows/deploy.yml

## ── Images ──────────────────────────────────────────────────────────────────
images: build-jobtracker build-voice

build-jobtracker:
	docker build -f docker/jobtracker/Dockerfile apps/jobtracker \
	  -t $(IMAGE_JOBTRACK)
	@echo "jobtracker image size: $$(docker image inspect $(IMAGE_JOBTRACK) --format '{{.Size}}' | numfmt --to=iec)"

build-voice:
	# voice-agent Dockerfile uses repo root as context (needs apps/voice-agent/app/)
	docker build -f docker/voice-agent/Dockerfile . \
	  -t $(IMAGE_VOICE)
	@echo "voice-agent image size: $$(docker image inspect $(IMAGE_VOICE) --format '{{.Size}}' | numfmt --to=iec)"

## ── Kind cluster ────────────────────────────────────────────────────────────
kind-up: images
	@echo "==> Creating kind cluster $(CLUSTER_NAME)"
	kind create cluster --config kind-config.yaml --name $(CLUSTER_NAME) || true
	@echo "==> Loading images into kind"
	kind load docker-image $(IMAGE_JOBTRACK) --name $(CLUSTER_NAME)
	kind load docker-image $(IMAGE_VOICE) --name $(CLUSTER_NAME)
	kind load docker-image pgvector/pgvector:pg17 --name $(CLUSTER_NAME) || true
	kind load docker-image otel/opentelemetry-collector-contrib:latest --name $(CLUSTER_NAME) || true
	kind load docker-image prom/prometheus:latest --name $(CLUSTER_NAME) || true
	kind load docker-image grafana/grafana:latest --name $(CLUSTER_NAME) || true
	@echo "==> Installing ingress-nginx"
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/kind/deploy.yaml
	kubectl -n ingress-nginx wait --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
	@echo "==> Installing observability stack"
	$(MAKE) obs-up
	@echo "==> Installing Postgres"
	helm upgrade --install postgres charts/postgres --wait --timeout 120s
	@echo "==> Installing apps"
	$(MAKE) apps-up
	@echo "==> kind-up complete."

obs-up:
	kubectl apply -f scripts/observability-deploy.yaml

apps-up:
	@# Create secrets from env vars (set by keys.py run or CI)
	kubectl create secret generic jobtracker-secrets \
	  --from-literal=GROQ_API_KEY=$${GROQ_API_KEY:-dummy} \
	  --from-literal=GROQ_MODEL=$${GROQ_MODEL:-openai/gpt-oss-20b} \
	  --from-literal=DATABASE_URL="postgresql://postgres:devpassword@postgres-postgres:5432/resume_tracker" \
	  --from-literal=FERNET_KEY=$${FERNET_KEY:-} \
	  --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret generic voice-agent-secrets \
	  --from-literal=GROQ_API_KEY=$${GROQ_API_KEY:-dummy} \
	  --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install jobtracker charts/app-chart -f charts/values/jobtracker.yaml --wait --timeout 180s
	helm upgrade --install voice-agent charts/app-chart -f charts/values/voice-agent.yaml --wait --timeout 180s

kind-down:
	@echo "==> Deleting kind cluster $(CLUSTER_NAME)"
	kind delete cluster --name $(CLUSTER_NAME)
	@echo "==> kind-down complete."

## ── Smoke test ──────────────────────────────────────────────────────────────
smoke:
	@echo "==> Smoke tests via ingress"
	bash scripts/smoke.sh

## ── Load test ───────────────────────────────────────────────────────────────
k6:
	mkdir -p loadtest/results
	k6 run loadtest/k6-health.js --out json=loadtest/results/k6-result.json
	@echo "==> Querying Prometheus for RED metrics after load test"
	bash scripts/prom-query.sh

bench: k6

## ── Unit tests ──────────────────────────────────────────────────────────────
test:
	pytest tests/ -v --tb=short

## ── Terraform ───────────────────────────────────────────────────────────────
terraform-init:
	cd infra/aws && terraform init

## ── Clean ───────────────────────────────────────────────────────────────────
clean:
	docker rmi $(IMAGE_JOBTRACK) $(IMAGE_VOICE) 2>/dev/null || true
