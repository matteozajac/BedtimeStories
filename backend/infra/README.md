# Private voice infrastructure

The user-approved shared TestFlight/production project is `gen-lang-client-0154884984`, **Always Near Stories**. Its European foundation and private worker are deployed. [Deployment instructions](DEPLOYMENT.md) include importing the existing project, protected local state, Firebase Storage bucket registration, the explicit `cloud-audio` rules target, and safe Functions environment generation. See the [deployment receipt](../../docs/CLOUD_NARRATION_DEPLOYMENT.md) for current evidence.

Validated locally using official Terraform 1.14.0 in a temporary directory (release archive SHA256 verified): `terraform init -backend=false`, signed Google/Google Beta provider 8.2.0 installation, `terraform validate`, and `terraform fmt -check` all passed. `.terraform.lock.hcl` records the verified providers. Six offline helper tests passed with the worker's exact dependency environment; they reject foreign buckets, secret/unsafe environment fields, noncanonical worker URLs, and accidental feature activation, and verify the exact named Storage target.

Use `environments/shared.tfvars.example` and one protected state outside Git. The initial image is null; set the project-owned immutable image digest for the worker apply. Cloud narration remains disabled in the generated Functions environment until real voice/device validation. Cloud Run scales to zero and allocates CPU during requests. Schema validation alone does not establish live privacy or voice quality.

Run helper tests with `python3 -m unittest discover -s backend/infra/tests -v` after installing `backend/worker/requirements.txt`. No remote tests or registration are performed by the test suite.
