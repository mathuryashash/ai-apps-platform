# Runbook

## Deploy to AWS for the first time

### Prerequisites
- AWS account with admin-level credentials (for initial Terraform apply).
- `terraform`, `helm`, `kubectl`, `aws` CLI installed.
- Repository secret `AWS_DEPLOY_ROLE_ARN` set in GitHub (IAM role created by Terraform).

### Steps

1. **Provision infrastructure (once)**
   ```bash
   cd infra/aws
   terraform init   # configure S3 backend in versions.tf first
   terraform apply  # ~15 minutes; creates VPC, EKS, RDS, ECR, IAM
   ```
   Note the outputs: `deploy_role_arn`, `ecr_jobtracker_url`, `ecr_voice_agent_url`.

2. **Set GitHub secrets**
   - `AWS_DEPLOY_ROLE_ARN` = output from step 1
   - `GROQ_API_KEY` = your Groq API key (from https://console.groq.com)
   - `FERNET_KEY` = generate with `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`

3. **Seed Secrets Manager** (Terraform creates the secret shells with no value)
   ```bash
   aws secretsmanager put-secret-value \
     --secret-id ai-apps-platform/groq-api-key \
     --secret-string '{"GROQ_API_KEY":"gsk_..."}'
   aws secretsmanager put-secret-value \
     --secret-id ai-apps-platform/fernet-key \
     --secret-string '{"FERNET_KEY":"..."}'
   ```

4. **Configure kubectl**
   ```bash
   aws eks update-kubeconfig --name ai-apps-platform --region ap-south-1
   ```

5. **Install ingress-nginx on EKS**
   ```bash
   helm upgrade --install ingress-nginx ingress-nginx \
     --repo https://kubernetes.github.io/ingress-nginx \
     --namespace ingress-nginx --create-namespace
   ```

6. **Install observability stack**
   ```bash
   kubectl apply -f scripts/observability-deploy.yaml
   ```

7. **Install apps via GitHub Actions**
   - Go to Actions → Deploy to EKS → Run workflow.
   - Or manually: `helm upgrade --install jobtracker charts/app-chart -f charts/values/jobtracker.yaml --set image.repository=<ECR_URL> --set image.tag=latest`

8. **Verify**
   ```bash
   kubectl get pods
   curl https://<ALB_DNS>/health -H "Host: jobtracker.local"
   ```

---

## Rollback

```bash
# Roll back to previous Helm release
helm rollback jobtracker
helm rollback voice-agent

# Or pin to a specific revision
helm rollback jobtracker 2
```

Kubernetes keeps the previous ReplicaSet around for instant rollback. The rolling update strategy means zero downtime if at least 1 pod is healthy.

---

## Reading the Grafana dashboard

Open Grafana at `http://localhost:18091` (local) or the EKS service URL.

**Dashboard: AI Apps Platform — RED Metrics**

| Panel | What to look for |
|---|---|
| Request Rate | Steady baseline, spikes correlate with traffic |
| Error Rate (5xx %) | Should be near 0; spike indicates app error or bad deploy |
| Latency p50/p95 | p50 < 200ms normal; p95 < 1s healthy; above 2s triggers alert |
| p95 by Route | Identify which route is slow (e.g. `/agent/run` vs `/health`) |

---

## Alert meanings

| Alert | Meaning | Action |
|---|---|---|
| `High5xxRate` | >5% of requests returning 5xx for 2 minutes | Check app logs: `kubectl logs -l app.kubernetes.io/name=jobtracker --tail=50` |
| `HighP95Latency` | p95 latency >2s for 3 minutes | Check if LLM upstream is slow (Groq status page); check DB connection pool |
| `PodRestartStorm` | Pod restarted >3 times in 15 minutes | Check for OOMKill (`kubectl describe pod <name>`); may need to increase memory limit |

---

## Common troubleshooting

**Pod stuck in CrashLoopBackOff:**
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name> --previous
```

**Database connection refused:**
- Verify Postgres is running: `kubectl get pods -l app.kubernetes.io/name=postgres`
- Check the DATABASE_URL secret: `kubectl get secret jobtracker-secrets -o jsonpath='{.data.DATABASE_URL}' | base64 -d`

**OTel traces not appearing:**
- Check collector is running: `kubectl logs deployment/otel-collector`
- Check OTEL_EXPORTER_OTLP_ENDPOINT env var points to `otel-collector:4317`

**Helm upgrade fails:**
```bash
helm history <release-name>  # see past revisions
helm rollback <release-name>  # go back
```
