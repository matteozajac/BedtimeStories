# Private voice infrastructure

The dedicated staging/production Terraform module and helper scripts are ready for review. **Nothing here has been applied:** personal Google Cloud project quota blocked the staging project on 2026-10-02. [Deployment instructions](DEPLOYMENT.md) include the separate Firebase Storage bucket registration, explicit `cloud-audio` rules target, identifier-only Functions environment generation, and required live checks.

Validated locally using official Terraform 1.14.0 in a temporary directory (release archive SHA256 verified): `terraform init -backend=false`, signed Google/Google Beta provider 8.2.0 installation, `terraform validate`, and `terraform fmt -check` all passed. `.terraform.lock.hcl` records the verified providers. Six offline helper tests passed with the worker's exact dependency environment; they reject foreign buckets, secret/unsafe environment fields, noncanonical worker URLs, and accidental feature activation, and verify the exact named Storage target.

Use independent protected Terraform states for `environments/staging.tfvars.example` and `environments/production.tfvars.example`. The initial image is null, so foundation can be provisioned before building the private worker; set its project-owned immutable image digest for the second apply. Cloud narration remains disabled in the generated Functions environment. Successful schema validation does not establish project provisioning, IAM effectiveness, Gemini access, Firebase identity/App Check configuration, or physical-device voice quality.

Run helper tests with `python3 -m unittest discover -s backend/infra/tests -v` after installing `backend/worker/requirements.txt`. No remote tests or registration are performed by the test suite.
