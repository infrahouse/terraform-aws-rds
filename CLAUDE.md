# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## First Steps

**Your first tool call in this repository MUST be reading .claude/CODING_STANDARD.md.
Do not read any other files, search, or take any actions until you have read it.**
This contains InfraHouse's comprehensive coding standards for Terraform, Python, and general formatting rules.

## Repository Overview

This is `terraform-aws-rds` -- an InfraHouse Terraform module for provisioning AWS RDS instances with CloudWatch alarms, security hardening, Vanta compliance tags, and severity-based alert notifications. The module is in the InfraHouse ecosystem and follows InfraHouse conventions throughout.

Design requirements and context are in `.claude/plans/rds-pod-requirements-context.local.md`.

## Key Commands

```bash
make bootstrap       # Install dependencies and pre-commit hooks
make test            # Run full pytest integration test suite
make test-keep       # Run tests, keep AWS infrastructure for debugging
make test-clean      # Run tests with cleanup (run before PRs)
make lint            # Check formatting (terraform fmt, yamllint)
make format          # Auto-format (terraform fmt, black)
make release-patch   # Release patch version (runs git-cliff + bumpversion)
make release-minor   # Release minor version
make release-major   # Release major version
```

Run a single test: `pytest tests/test_foo.py::test_bar -k "aws-6"`

## Architecture

- **Module source**: Files in root (`main.tf`, `variables.tf`, `outputs.tf`, `locals.tf`, `alarms.tf`, `versions.tf`, etc.)
- **Tests**: `tests/` directory using pytest + pytest-infrahouse fixtures (integration tests that create real AWS infrastructure)
- **Examples**: `examples/` directory with working usage examples
- **Docs**: `docs/` for MkDocs GitHub Pages site (Material theme)

Key design patterns:
- CloudWatch alarms use severity-based SNS topics (urgent/high/normal) -- users pass SNS topic ARNs per severity, not per alarm
- Vanta compliance tags (`VantaOwner`, `VantaNonProd`, `VantaContainsUserData`, etc.) are applied to the RDS instance
- Deletion protection is enabled by default
- Storage encryption uses KMS

## InfraHouse Conventions

- **Module registry**: Use `registry.infrahouse.com` (not the public Terraform Registry) for InfraHouse modules
- **Version pinning**: Always exact versions for module sources (no `~>` ranges); Renovate manages updates
- **Commit messages**: Conventional Commits required (`feat:`, `fix:`, `docs:`, etc.) -- enforced by `hooks/commit-msg`
- **Pre-commit hooks**: `hooks/pre-commit` runs `terraform fmt -check`, `terraform-docs`, and trailing newline checks
- **Tags**: Lowercase (except `Name`), use underscores for multi-word. Required: `environment` (from user, no default), `created_by_module`, provenance tags
- **IAM policies**: Always use `aws_iam_policy_document` data source, never `jsonencode()`
- **Secrets**: Use `infrahouse/secret/aws` module; never hardcode values
- **Line length**: 120 characters max for all files
- **All files must end with a newline**

## Validation Blocks

Always use ternary for nullable variable validation (Terraform OR doesn't short-circuit null):
```hcl
# WRONG:  condition = var.x == null || var.x <= 100
# RIGHT:  condition = var.x == null ? true : var.x <= 100
```

## Testing

Tests are pytest-based integration tests that provision real AWS infrastructure. They use:
- **pytest-infrahouse** for Terraform fixtures
- **infrahouse-core** for AWS validation helpers
- AWS provider v6+ (`@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])`)
- Test role: configured via Makefile variables (`TEST_ROLE`, `TEST_REGION`)

## Managed Files (Do Not Edit)

These files are managed by the `github-control` repository -- changes will be overwritten:
- `.terraform-docs.yml`
- `.claude/CODING_STANDARD.md`
- `mkdocs.yml`
- `cliff.toml`
- `.github/workflows/` (most workflow files)

## Reference Implementation

See [terraform-aws-actions-runner](https://github.com/infrahouse/terraform-aws-actions-runner) for a complete example of InfraHouse module structure, documentation, and testing patterns.