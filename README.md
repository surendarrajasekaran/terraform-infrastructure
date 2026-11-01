# Terraform infrastructure

Reusable AWS and GCP modules, sourced by application roots that supply environment settings. This repository provisions cloud resources. The AWS root also installs Argo CD through Terraform's Helm provider.

| Repository | Responsibility |
| --- | --- |
| **terraform-infrastructure** — this private repository | Cloud resources, state configuration and the AWS Argo controller |
| [infra-helm-charts](https://github.com/surendarrajasekaran/infra-helm-charts#readme) | Helm values, parent/child Applications, app bootstrap and health/recovery |
| [om-idea-board](https://github.com/surendarrajasekaran/om-idea-board#readme) | App code, tests, image publishing and AI resource planning |

## Structure

```text
modules/
  aws/              VPC, EKS, PostgreSQL, ECR, publisher access and Argo CD
  gcp/              Network, GKE and PostgreSQL
apps/onboard/
  aws/              AWS module calls, inputs, backend and Argo values
  gcp/              GCP module calls, inputs and backend
```

Change reusable behavior in `modules/`; pass target-specific settings from `apps/onboard/`. PRs validate formatting, lint and syntax. Provisioning runs explicitly from an authorized operator machine.

## Prerequisites

Install Git, Terraform **1.11.4** and your cloud CLI. AWS needs AWS CLI v2 available to the Helm provider. Install `kubectl` for the later GitOps bootstrap.

You need permission to provision the target and access its state. Supply your own account/project, region, administrator access, network ranges and GitHub settings. Backend storage must exist before init: encrypted S3 with locking for AWS, or a versioned GCS bucket for GCP. Set an existing GitHub OIDC provider ARN when reusing one; otherwise the enabled publisher module can create it.

Terraform's Helm provider must reach the EKS API through approved private routing or a restricted public endpoint. Review `apps/onboard/aws/argocd-values.yaml` for a new target: controller images must be available to its cluster. Terraform does not copy image mirrors between registries.

## AWS configuration files

| File | Purpose |
| --- | --- |
| `apps/onboard/aws/main.tf` | Calls the AWS infrastructure and Argo modules |
| `apps/onboard/aws/terraform.tfvars.example` | Starting point for a new environment |
| `apps/onboard/aws/aws-test.tfvars` | Versioned non-secret inputs for an existing target |
| `apps/onboard/aws/backend.test.hcl` | That target's state location and encryption/locking settings |
| `apps/onboard/aws/argocd-values.yaml` | Controller settings and pinned images |

The committed target files belong to an existing stack. Reuse them only for that stack. A new stack needs its own inputs and backend key. Credentials, kubeconfigs, state and saved plans are excluded from Git; state and plans can still contain database credentials.

## Run against an existing AWS target

Replace the uppercase placeholders with your authorized profile and region. If the profile uses SSO, authenticate before planning.

```sh
git clone https://github.com/surendarrajasekaran/terraform-infrastructure.git
cd terraform-infrastructure
export AWS_PROFILE="YOUR_AWS_PROFILE"
export AWS_REGION="YOUR_AWS_REGION"
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity

terraform -chdir=apps/onboard/aws init -reconfigure -backend-config=backend.test.hcl
terraform -chdir=apps/onboard/aws plan -var-file=aws-test.tfvars -out=reviewed.tfplan
# Review the plan before applying it.
terraform -chdir=apps/onboard/aws apply reviewed.tfplan
rm apps/onboard/aws/reviewed.tfplan
```

Verify the identity and `aws_account_id` guard match the intended target. Keep its existing state key and module addresses. Maintenance uses a full plan, without `-target`.

## Create a new AWS target

From the repository root, copy the example and replace all target-specific settings, including repository/OIDC references and administrator CIDRs. The example is not deployment-ready.

```sh
cp apps/onboard/aws/terraform.tfvars.example apps/onboard/aws/terraform.tfvars
mkdir -p artifacts/aws
```

Create `artifacts/aws/backend.hcl` using your existing backend resources. `artifacts/` and local `terraform.tfvars` are ignored by Git.

```hcl
bucket       = "YOUR_STATE_BUCKET"
key          = "YOUR_PROJECT/YOUR_ENVIRONMENT/terraform.tfstate"
region       = "YOUR_STATE_BUCKET_REGION"
encrypt      = true
use_lockfile = true
kms_key_id   = "YOUR_KMS_KEY_ARN"
```

Authenticate as above. A fresh EKS cluster must exist and be reachable before the Helm provider installs Argo, so initial provisioning has two phases:

```sh
terraform -chdir=apps/onboard/aws init -reconfigure \
  -backend-config="$PWD/artifacts/aws/backend.hcl"
terraform -chdir=apps/onboard/aws plan -var-file=terraform.tfvars \
  -target=module.aws -out=infra.tfplan
terraform -chdir=apps/onboard/aws apply infra.tfplan

# Establish approved network access to the created EKS API.
terraform -chdir=apps/onboard/aws plan -var-file=terraform.tfvars -out=full.tfplan
terraform -chdir=apps/onboard/aws apply full.tfplan
rm apps/onboard/aws/infra.tfplan apps/onboard/aws/full.tfplan
```

Review each plan before applying it. Use targeting only for initial cluster creation; subsequent changes use the full root. Provisioning creates billable resources.

## Argo installation and application handoff

`apps/onboard/aws` sources `modules/aws/argocd`, which owns Helm release `argocd` in namespace `argocd`. The provider reads the EKS endpoint/CA and uses `aws eks get-token` for short-lived authentication. No separate Argo installer or manual Helm install is needed.

When adopting an existing Argo release into a different Terraform state, import it once before planning with that target's input file:

```sh
terraform -chdir=apps/onboard/aws import -var-file=terraform.tfvars \
  module.argocd.helm_release.argocd argocd/argocd
```

An already managed release needs no further import. Terraform owns the controller; Argo owns the applications. After apply, configure an operator Kubernetes context:

```sh
CLUSTER_NAME="$(terraform -chdir=apps/onboard/aws output -raw cluster_name)"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
kubectl -n argocd get deployments
```

Continue with [GitOps first-time setup](https://github.com/surendarrajasekaran/infra-helm-charts#first-time-setup). It prepares the namespace/Secrets and bootstraps scoped projects plus **one parent Application**. The parent creates both service Applications.

| Output | Used for |
| --- | --- |
| `cluster_name`, `region` | Operator cluster connection |
| `repository_urls`, `ecr_push_role_arn` | App Actions registry and OIDC settings |
| `database_egress_cidrs` | Actions network-policy input, as a JSON array |
| `database_url` | Runtime Secret; sensitive |
| `migration_database_url`, `application_password` | Migration Secret; sensitive |
| `database_ca_certificate` | GCP database CA; AWS uses its RDS trust bundle separately |

## GCP infrastructure

The GCP root provisions network, GKE and PostgreSQL. Live GCP application delivery remains outstanding; this root does not install Argo or provide a completed GCP release workflow.

Install the Google Cloud CLI, select an authorized project, create a separate versioned GCS state bucket and edit the inputs.

```sh
gcloud auth application-default login
cp apps/onboard/gcp/terraform.tfvars.example apps/onboard/gcp/terraform.tfvars
# Edit project, region, administrator CIDRs and network settings.
terraform -chdir=apps/onboard/gcp init -reconfigure \
  -backend-config="bucket=YOUR_STATE_BUCKET" \
  -backend-config="prefix=YOUR_PROJECT/YOUR_ENVIRONMENT"
terraform -chdir=apps/onboard/gcp plan -out=reviewed.tfplan
# Review, then apply.
terraform -chdir=apps/onboard/gcp apply reviewed.tfplan
rm apps/onboard/gcp/reviewed.tfplan
```

## Validation and troubleshooting

[Terraform checks](.github/workflows/validate.yml) runs formatting, TFLint and backend-disabled init/validate for both roots. It does not access state, plan or apply. Keep provider lock files committed for reproducible local and Linux CI runs.

```sh
terraform fmt -check -recursive
tflint --recursive --format compact
terraform -chdir=apps/onboard/aws init -backend=false -input=false -lockfile=readonly
terraform -chdir=apps/onboard/aws validate
terraform -chdir=apps/onboard/gcp init -backend=false -input=false -lockfile=readonly
terraform -chdir=apps/onboard/gcp validate
```

Renew expired cloud logins before operating. If Argo installation times out, verify EKS API reachability and image access. Backend-disabled validation is for configuration checks; initialize the real backend again before provisioning.
