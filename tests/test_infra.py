"""
Unit tests for ai-apps-platform infrastructure definitions.
These tests do NOT require Docker, Kubernetes, or AWS credentials.
They validate Helm chart structure, Kubernetes manifests, and config files.
"""
import json
import os
import subprocess
import sys
import yaml
import pytest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def helm_template(release_name, values_file=None):
    """Render a Helm chart and return parsed YAML documents."""
    cmd = ["helm", "template", release_name, os.path.join(REPO_ROOT, "charts", "app-chart")]
    if values_file:
        cmd += ["-f", os.path.join(REPO_ROOT, "charts", "values", values_file)]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    docs = list(yaml.safe_load_all(result.stdout))
    return [d for d in docs if d is not None]


def find_kind(docs, kind):
    return [d for d in docs if d.get("kind") == kind]


class TestHelmChart:
    """Validate the app-chart renders correctly with both app value sets."""

    def test_jobtracker_deployment_exists(self):
        docs = helm_template("jobtracker", "jobtracker.yaml")
        deployments = find_kind(docs, "Deployment")
        assert len(deployments) == 1
        assert deployments[0]["metadata"]["name"] == "jobtracker"

    def test_voice_agent_deployment_exists(self):
        docs = helm_template("voice-agent", "voice-agent.yaml")
        deployments = find_kind(docs, "Deployment")
        assert len(deployments) == 1
        assert deployments[0]["metadata"]["name"] == "voice-agent"

    def test_deployment_non_root(self):
        """Security: containers must run as non-root."""
        docs = helm_template("jobtracker", "jobtracker.yaml")
        deployment = find_kind(docs, "Deployment")[0]
        pod_spec = deployment["spec"]["template"]["spec"]
        security_ctx = pod_spec.get("securityContext", {})
        assert security_ctx.get("runAsNonRoot") is True, "Pod must run as non-root"
        assert security_ctx.get("runAsUser", 0) > 0, "runAsUser must be > 0"

    def test_container_drops_all_capabilities(self):
        """Security: containers must drop ALL Linux capabilities."""
        docs = helm_template("jobtracker", "jobtracker.yaml")
        deployment = find_kind(docs, "Deployment")[0]
        container = deployment["spec"]["template"]["spec"]["containers"][0]
        caps = container.get("securityContext", {}).get("capabilities", {})
        assert "ALL" in caps.get("drop", []), "Container must drop ALL capabilities"

    def test_resource_limits_set(self):
        """Resources must have both requests and limits (prevents unbounded consumption)."""
        docs = helm_template("jobtracker", "jobtracker.yaml")
        deployment = find_kind(docs, "Deployment")[0]
        resources = deployment["spec"]["template"]["spec"]["containers"][0]["resources"]
        assert "requests" in resources
        assert "limits" in resources
        assert "cpu" in resources["requests"]
        assert "memory" in resources["requests"]

    def test_liveness_probe_configured(self):
        docs = helm_template("jobtracker", "jobtracker.yaml")
        deployment = find_kind(docs, "Deployment")[0]
        container = deployment["spec"]["template"]["spec"]["containers"][0]
        assert "livenessProbe" in container, "livenessProbe must be set"
        assert container["livenessProbe"]["httpGet"]["path"] == "/health"

    def test_readiness_probe_configured(self):
        docs = helm_template("jobtracker", "jobtracker.yaml")
        deployment = find_kind(docs, "Deployment")[0]
        container = deployment["spec"]["template"]["spec"]["containers"][0]
        assert "readinessProbe" in container, "readinessProbe must be set"

    def test_hpa_configured(self):
        docs = helm_template("jobtracker", "jobtracker.yaml")
        hpas = find_kind(docs, "HorizontalPodAutoscaler")
        assert len(hpas) == 1
        hpa = hpas[0]
        assert hpa["spec"]["maxReplicas"] == 3

    def test_pdb_configured(self):
        docs = helm_template("jobtracker", "jobtracker.yaml")
        pdbs = find_kind(docs, "PodDisruptionBudget")
        assert len(pdbs) == 1

    def test_ingress_configured(self):
        docs = helm_template("jobtracker", "jobtracker.yaml")
        ingresses = find_kind(docs, "Ingress")
        assert len(ingresses) == 1
        assert ingresses[0]["spec"]["ingressClassName"] == "nginx"

    def test_otel_env_vars_present(self):
        """OTel instrumentation env vars must be injected via the chart."""
        docs = helm_template("jobtracker", "jobtracker.yaml")
        deployment = find_kind(docs, "Deployment")[0]
        env = deployment["spec"]["template"]["spec"]["containers"][0].get("env", [])
        env_names = {e["name"] for e in env}
        assert "OTEL_EXPORTER_OTLP_ENDPOINT" in env_names
        assert "OTEL_SERVICE_NAME" in env_names

    def test_voice_agent_target_port(self):
        """voice-agent must expose port 7860 (not 8000)."""
        docs = helm_template("voice-agent", "voice-agent.yaml")
        deployment = find_kind(docs, "Deployment")[0]
        container = deployment["spec"]["template"]["spec"]["containers"][0]
        ports = {p["name"]: p["containerPort"] for p in container.get("ports", [])}
        assert ports.get("http") == 7860, f"voice-agent containerPort must be 7860, got {ports}"


class TestPrometheusRules:
    """Validate the Prometheus alert rules file is parseable YAML with required alerts."""

    def _load_rules(self):
        path = os.path.join(REPO_ROOT, "observability", "rules", "app-alerts.yml")
        with open(path) as f:
            return yaml.safe_load(f)

    def test_rules_file_valid_yaml(self):
        rules = self._load_rules()
        assert rules is not None
        assert "groups" in rules

    def test_required_alerts_exist(self):
        rules = self._load_rules()
        all_alerts = set()
        for group in rules["groups"]:
            for rule in group.get("rules", []):
                if "alert" in rule:
                    all_alerts.add(rule["alert"])
        assert "High5xxRate" in all_alerts
        assert "HighP95Latency" in all_alerts
        assert "PodRestartStorm" in all_alerts

    def test_alerts_have_severity_label(self):
        rules = self._load_rules()
        for group in rules["groups"]:
            for rule in group.get("rules", []):
                if "alert" in rule:
                    assert "severity" in rule.get("labels", {}), (
                        f"Alert {rule['alert']} missing severity label"
                    )


class TestGrafanaDashboard:
    """Validate the Grafana dashboard JSON."""

    def _load_dashboard(self):
        path = os.path.join(REPO_ROOT, "observability", "grafana-dashboard.json")
        with open(path) as f:
            return json.load(f)

    def test_dashboard_valid_json(self):
        d = self._load_dashboard()
        assert "panels" in d
        assert len(d["panels"]) >= 4

    def test_dashboard_has_required_panels(self):
        d = self._load_dashboard()
        titles = {p["title"] for p in d["panels"]}
        assert any("Rate" in t or "rate" in t for t in titles), "Missing request rate panel"
        assert any("Error" in t or "error" in t for t in titles), "Missing error rate panel"
        assert any("Latency" in t or "latency" in t for t in titles), "Missing latency panel"

    def test_dashboard_uses_prometheus_datasource(self):
        d = self._load_dashboard()
        for panel in d["panels"]:
            ds = panel.get("datasource", {})
            if isinstance(ds, dict):
                assert ds.get("type") == "prometheus"


class TestOtelCollectorConfig:
    """Validate OTel collector config."""

    def _load_config(self):
        path = os.path.join(REPO_ROOT, "observability", "otel-collector-config.yaml")
        with open(path) as f:
            return yaml.safe_load(f)

    def test_otlp_receiver_configured(self):
        cfg = self._load_config()
        assert "otlp" in cfg["receivers"]

    def test_prometheus_exporter_configured(self):
        cfg = self._load_config()
        assert "prometheus" in cfg["exporters"]

    def test_metrics_pipeline_exists(self):
        cfg = self._load_config()
        assert "metrics" in cfg["service"]["pipelines"]

    def test_traces_pipeline_exists(self):
        cfg = self._load_config()
        assert "traces" in cfg["service"]["pipelines"]


class TestKindConfig:
    """Validate the kind cluster config."""

    def test_kind_config_valid(self):
        path = os.path.join(REPO_ROOT, "kind-config.yaml")
        with open(path) as f:
            cfg = yaml.safe_load(f)
        assert cfg["kind"] == "Cluster"
        # kind uses top-level `name` field, not metadata.name
        assert cfg.get("name") == "ai-apps-platform"

    def test_port_mappings_in_range(self):
        """All hostPort values must be in assigned range 18000-18099."""
        path = os.path.join(REPO_ROOT, "kind-config.yaml")
        with open(path) as f:
            cfg = yaml.safe_load(f)
        for node in cfg["nodes"]:
            for mapping in node.get("extraPortMappings", []):
                hp = mapping["hostPort"]
                assert 18000 <= hp <= 18099, (
                    f"hostPort {hp} outside assigned range 18000-18099"
                )
