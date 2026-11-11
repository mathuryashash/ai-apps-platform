# AWS Cost Estimate

> **This is an estimate, not a bill. No AWS account exists; no resources were provisioned.**
> Prices are from the [AWS pricing page](https://aws.amazon.com/pricing/) as of November 2026, ap-south-1 (Mumbai).
> Actual costs depend on traffic, data transfer, and reserved pricing.

## Resources

| Resource | Spec | $/mo (on-demand) | Notes |
|---|---|---|---|
| EKS control plane | 1 cluster | $73 | Flat per-cluster fee |
| EC2 (node group) | 2× t3.medium (2 vCPU, 4 GB) | $60 | ~$0.0416/hr × 2 × 720h |
| RDS Postgres 17 | db.t3.micro, 20 GB gp3, single-AZ | $20 | ~$0.025/hr + storage |
| NAT Gateway | 1× (single-AZ) | $33 | $0.045/hr + data processing |
| ECR | 2 repos, ~1 GB each | $0.10 | $0.10/GB/mo after 500 MB free |
| Secrets Manager | 2 secrets | $0.80 | $0.40/secret/mo |
| CloudWatch Logs | EKS control plane logs | $3 | ~3 GB/mo × $0.50/GB ingestion |
| ALB (ingress-nginx) | 1 load balancer | $18 | ~$0.025/hr + LCU |
| Data transfer | Minimal (dev workload) | $5 | Estimate |

**Total estimate: ~$213/month**

## Assumptions

- 2 EC2 nodes running 24/7 (no Spot, no savings plan).
- RDS single-AZ (flip `multi_az = true` for production, adds ~$20/mo).
- NAT Gateway: `enable_nat_gateway = false` removes $33/mo (nodes lose outbound internet; pull from ECR via VPC endpoint instead).
- EKS control plane: cannot be turned off; $73/mo is unavoidable.
- No data transfer charges for typical dev-scale traffic (<1 GB/day out).

## Cost reduction options

1. **Spot instances:** Replace on-demand nodes with Spot t3.medium (~70% discount = $18/mo for 2 nodes).
2. **Savings Plan:** 1-year compute savings plan reduces EC2 ~40%.
3. **Remove NAT Gateway:** Use VPC endpoints for ECR, S3, Secrets Manager ($0.01/hr each = ~$7.20/mo vs $33/mo NAT).
4. **Schedule scale-down:** Scale node group to 0 outside business hours if this is a dev cluster.

## Pricing page links

- EKS: https://aws.amazon.com/eks/pricing/
- EC2: https://aws.amazon.com/ec2/pricing/on-demand/
- RDS: https://aws.amazon.com/rds/pricing/
- NAT Gateway: https://aws.amazon.com/vpc/pricing/
- ECR: https://aws.amazon.com/ecr/pricing/
- Secrets Manager: https://aws.amazon.com/secrets-manager/pricing/
- CloudWatch: https://aws.amazon.com/cloudwatch/pricing/
