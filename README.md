# Terraform infrastructure

Reusable Terraform modules, called by the AWS and GCP application roots.

```text
modules/
  aws/              Network, EKS, PostgreSQL, ECR, publisher access and Argo CD
  gcp/              Network, GKE and PostgreSQL
apps/onboard/
  aws/              Running AWS inputs, backend settings and module calls
  gcp/              GCP inputs and module calls
```

There are no tests, state-bootstrap utilities, Python installers or private-access scripts here. Pull requests run formatting, TFLint and backend-disabled Terraform validation only. They do not plan, apply or require cloud credentials.

## Running AWS configuration

| File | Purpose |
| --- | --- |
| `apps/onboard/aws/main.tf` | Calls the AWS infrastructure and Argo modules |
| `apps/onboard/aws/aws-test.tfvars` | Actual non-secret settings for the running test |
| `apps/onboard/aws/backend.test.hcl` | Actual S3 state bucket, key, encryption and locking settings |
| `apps/onboard/aws/argocd-values.yaml` | Argo controller settings and pinned images |

These configuration files are versioned in this private repository. Credentials, kubeconfigs, Terraform state and saved plans are excluded. The existing state bucket, encryption key and GitHub OIDC provider are prerequisites; this repo does not bootstrap or destroy them.

## Run against the existing AWS test

Install Terraform **1.11.4**, AWS CLI v2 and Git. Use the authorized SSO profile. The machine running Terraform must reach the EKS API through private routing or its approved public allowlist.

```sh
git clone https://github.com/surendarrajasekaran/terraform-infrastructure.git
cd terraform-infrastructure
export AWS_PROFILE=mit-qa-administratoraccess
export AWS_REGION=us-west-2
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity --query Account --output text

terraform -chdir=apps/onboard/aws init -reconfigure -backend-config=backend.test.hcl
terraform -chdir=apps/onboard/aws plan -var-file=aws-test.tfvars -out=reviewed.tfplan
# Review the plan, then explicitly apply it:
terraform -chdir=apps/onboard/aws apply reviewed.tfplan
rm apps/onboard/aws/reviewed.tfplan
```

Expected account: `812752207041`; region: `us-west-2`; cluster: `idea-board-test`. Review changes to the committed inputs before applying. Keep the existing backend key: it identifies the running stack's state. Do not use example defaults against existing state. The current endpoint has private access and one restricted public allowlist entry.

## How Argo is installed

`apps/onboard/aws` calls `modules/aws/argocd`. That module manages Helm release `argocd` through the Terraform Helm provider. **There is no separate script or manual Helm installation.** The provider reads EKS endpoint/CA data and obtains short-lived authentication through `aws eks get-token`; no Kubernetes token is stored in tfvars.

The existing Argo release is imported into this Terraform state rather than installed a second time. If adopting a different preexisting release, import it once before applying:

```sh
terraform -chdir=apps/onboard/aws import -var-file=aws-test.tfvars \
  module.argocd.helm_release.argocd argocd/argocd
```

The root Argo Application and two service Applications remain in [infra-helm-charts](https://github.com/surendarrajasekaran/infra-helm-charts). Terraform owns the Argo controller; Argo owns application deployment. The [app repo](https://github.com/surendarrajasekaran/om-idea-board) builds images and updates GitOps values. Controller values currently use the reviewed image mirror in this AWS account; update that mirror/configuration when onboarding another account.

## New AWS stack

Copy the example inputs to a separate private file, set its account/region/name/network/GitHub settings, and create a separate backend configuration using an existing encrypted state bucket. Never point a new stack at the running test's backend key.

An EKS cluster must exist and be reachable before the Helm provider can install Argo. For a fresh stack, provision the cloud module first, establish API connectivity, then run the full plan/apply:

```sh
terraform -chdir=apps/onboard/aws init -backend-config=YOUR_BACKEND.hcl
terraform -chdir=apps/onboard/aws plan -var-file=YOUR_INPUTS.tfvars \
  -target=module.aws -out=infra.tfplan
terraform -chdir=apps/onboard/aws apply infra.tfplan
# Establish approved network access to the created EKS API.
terraform -chdir=apps/onboard/aws plan -var-file=YOUR_INPUTS.tfvars -out=full.tfplan
terraform -chdir=apps/onboard/aws apply full.tfplan
```

Use the targeted step only for initial cluster bootstrap. Normal changes use a full plan. Cloud creation incurs charges. State/plan files may contain database credentials; never commit or upload them.

## GCP

The GCP root provisions cloud infrastructure; live GCP application delivery is still pending. Set an authorized Google project and use a separate existing versioned GCS state bucket.

```sh
gcloud auth application-default login
cp apps/onboard/gcp/terraform.tfvars.example apps/onboard/gcp/terraform.tfvars
# Edit project, region and network settings in terraform.tfvars.
terraform -chdir=apps/onboard/gcp init \
  -backend-config="bucket=YOUR_STATE_BUCKET" -backend-config="prefix=idea-board/staging"
terraform -chdir=apps/onboard/gcp plan -out=reviewed.tfplan
terraform -chdir=apps/onboard/gcp apply reviewed.tfplan
```

## PR checks

The [workflow](.github/workflows/validate.yml) runs `terraform fmt -check -recursive`, TFLint and `terraform init -backend=false` / `terraform validate` for the two roots. Provider/module versions are pinned. Lock files are required for reproducible Linux CI and local runs.
