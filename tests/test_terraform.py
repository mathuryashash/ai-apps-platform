"""
Terraform module structure tests — validate .tf file syntax and key security settings.
Does not require AWS credentials or terraform init.
"""
import os
import re
import pytest

INFRA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "infra", "aws")


def read_tf(filename):
    with open(os.path.join(INFRA_DIR, filename)) as f:
        return f.read()


class TestTerraformSecurity:
    """Static checks on Terraform source for security invariants."""

    def test_rds_not_publicly_accessible(self):
        rds = read_tf("rds.tf")
        assert "publicly_accessible = false" in rds, (
            "RDS must set publicly_accessible = false"
        )

    def test_rds_storage_encrypted(self):
        rds = read_tf("rds.tf")
        assert "storage_encrypted = true" in rds, "RDS must have storage_encrypted = true"

    def test_oidc_trust_limited_to_main_branch(self):
        iam = read_tf("iam.tf")
        assert "refs/heads/main" in iam, (
            "OIDC trust policy must be scoped to refs/heads/main"
        )

    def test_no_hardcoded_secrets(self):
        for fname in os.listdir(INFRA_DIR):
            if not fname.endswith(".tf"):
                continue
            content = read_tf(fname)
            # Look for patterns that look like real API keys
            assert not re.search(r"gsk_[A-Za-z0-9]{20,}", content), (
                f"Potential Groq key in {fname}"
            )
            assert not re.search(r"AKIA[A-Z0-9]{16}", content), (
                f"Potential AWS access key in {fname}"
            )

    def test_eks_private_endpoint_enabled(self):
        eks = read_tf("eks.tf")
        assert "endpoint_private_access  = true" in eks or "endpoint_private_access = true" in eks

    def test_eks_cluster_logs_enabled(self):
        eks = read_tf("eks.tf")
        assert "enabled_cluster_log_types" in eks, "EKS cluster logs must be enabled"
