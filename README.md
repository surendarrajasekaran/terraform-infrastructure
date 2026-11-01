# Terraform infrastructure

Private infrastructure repository for the Idea Board platform. Terraform owns AWS/GCP resources; Argo owns application deployment.

```text
modules/
  aws/                 Reusable network, EKS, PostgreSQL, ECR and CI-access modules
  gcp/                 Reusable network, GKE and PostgreSQL modules
apps/onboard/
  aws/                 AWS root, example inputs, Argo bootstrap and private access
  gcp/                 GCP root and example inputs
```

`apps/onboard/aws/state-bootstrap` is the one-time account setup for encrypted state and optional GitHub OIDC. `apps/onboard/aws/argocd` holds the reviewed controller chart/image locks and Helm values. Each cloud root has its own provider lock and state. There is no cloud-switching root.

## Choose the right task

| Task | Where/how |
| --- | --- |
| Change app code and deploy | [om-idea-board](https://github.com/surendarrajasekaran/om-idea-board): PR, merge, release pipeline |
| Change chart/image/resource values | [infra-helm-charts](https://github.com/surendarrajasekaran/infra-helm-charts): GitOps PR; Argo reconciles |
| Change cloud resources | This repo: PR checks, then an operator reviews/applies a saved Terraform plan |
| Install/upgrade the Argo controller | This repo's AWS bootstrap helper, through the private cluster connection |

Normal app releases do not need Terraform or Kubernetes administrator credentials.

## Prerequisites

Use an authorized GitHub account to clone this private repo. Install Terraform **1.11.4**, Git, AWS CLI v2, Session Manager plugin, Python 3.12, kubectl compatible with the cluster, and Helm 3.19. TFLint **0.65.0** is needed for local lint. GCP provisioning also requires Google Cloud CLI and Application Default Credentials.

```sh
git clone https://github.com/surendarrajasekaran/terraform-infrastructure.git
git clone https://github.com/surendarrajasekaran/infra-helm-charts.git
cd terraform-infrastructure
python3.12 -m venv .venv
.venv/bin/pip install -r apps/onboard/aws/requirements.txt
umask 077
```

Keep credentials, actual tfvars, backend configuration, plans, state and kubeconfigs outside Git. They are ignored. Never print/upload all Terraform outputs: some contain database credentials.

## Provision or review AWS

The current test uses account `812752207041`, SSO profile `mit-qa-administratoraccess`, `us-west-2`, name `idea-board`, environment `test`.

```sh
export AWS_PROFILE=mit-qa-administratoraccess
export AWS_REGION=us-west-2
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity --query Account --output text
```

For the **existing test**, obtain its reviewed `aws-test.tfvars` from the platform operator. The local migration preserved it with the existing backend configuration. Do not use fresh example defaults against existing state. For a **new stack**, copy `apps/onboard/aws/terraform.tfvars.example` to a private `.tfvars` file and set the account, region, name, environment, administrator CIDRs and GitHub settings for that stack.

If this is a fresh clone, initialize the existing test backend as follows. For another stack, use its own bucket and `<name>/<environment>/terraform.tfstate` key.

```sh
cp apps/onboard/aws/backend.tf.example apps/onboard/aws/backend.tf
STATE_KMS_KEY_ARN=$(aws kms describe-key \
  --key-id alias/idea-board-terraform-state --region us-west-2 \
  --query KeyMetadata.Arn --output text)
terraform -chdir=apps/onboard/aws init -reconfigure \
  -backend-config="bucket=idea-board-tfstate-812752207041-us-west-2" \
  -backend-config="key=idea-board/test/terraform.tfstate" \
  -backend-config="region=us-west-2" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true" \
  -backend-config="kms_key_id=$STATE_KMS_KEY_ARN"
terraform -chdir=apps/onboard/aws plan \
  -var-file=aws-test.tfvars -out=reviewed.tfplan
# Review the resource changes before this explicit operator action:
terraform -chdir=apps/onboard/aws apply reviewed.tfplan
rm apps/onboard/aws/reviewed.tfplan
```

The account guard must match your intended AWS account. A new stack creates chargeable resources. Default control-plane access is private. Enable SSM access for the documented test tunnel; public API access is an explicit CIDR-restricted setting. For the existing test, preserve its reviewed endpoint configuration rather than replacing it with defaults.

Safe outputs for application pipeline configuration:

```sh
terraform -chdir=apps/onboard/aws output -raw cluster_name
terraform -chdir=apps/onboard/aws output -raw ecr_push_role_arn
terraform -chdir=apps/onboard/aws output -json repository_urls
terraform -chdir=apps/onboard/aws output -json database_egress_cidrs
```

The app repo's `aws-test` environment uses `AWS_ACCOUNT_ID`, `REGION`, `AWS_ECR_PUSH_ROLE_ARN`, `ECR_REGISTRY`, `ECR_REPOSITORY_PREFIX`, `DATABASE_EGRESS_CIDRS`, `PUBLIC_URL` and `GITOPS_REPOSITORY`. See its README for the deploy key, Gemini and release setup. Keep the publisher OIDC trust restricted to that app repo/environment. CI in this Terraform repo does not need an AWS role.

## Install Argo and bootstrap the app

Argo CD is installed with **Helm**, not a Terraform Helm provider. This avoids coupling initial EKS provisioning to a Kubernetes API that is not reachable until private routing exists. Only the controller is a Helm installation; the parent and two service Applications are reconciled by Argo.

For the current test, keep this process running in terminal 1:

```sh
.venv/bin/python apps/onboard/aws/private_eks.py \
  --profile mit-qa-administratoraccess --region us-west-2 \
  --cluster idea-board-test --kubeconfig artifacts/aws-test/kubeconfig.yaml
```

In terminal 2, from this repo:

```sh
export AWS_PROFILE=mit-qa-administratoraccess
export AWS_REGION=us-west-2
export KUBECONFIG="$PWD/artifacts/aws-test/kubeconfig.yaml"
kubectl --context idea-board-test get nodes
.venv/bin/python apps/onboard/aws/bootstrap_argocd.py \
  --context idea-board-test --account-id 812752207041 --region us-west-2 --check
# After preflight passes, repeat without --check to install/upgrade:
.venv/bin/python apps/onboard/aws/bootstrap_argocd.py \
  --context idea-board-test --account-id 812752207041 --region us-west-2
kubectl --context idea-board-test -n argocd get applications
```

The helper verifies the account, Terraform target, cluster CA, database network ranges and locked chart checksum. It bootstraps the Restricted namespace, database/CA/migration Secrets through stdin, installs Helm release `argocd`, then applies GitOps projects and `idea-board-controller`. No Secret bytes enter Git or logs. The GitOps controls must match the actual database CIDRs. The three Applications should become Synced/Healthy; wait for the GitOps health workflow before declaring the release successful.

The bundled Argo values are the **current AWS test configuration**: a reviewed Docker hardened image mirrored into that account's ECR, digest-pinned Redis and private UI. For another account, prepare its controller image mirror and review these values before bootstrap. A local chart archive can be supplied with `--chart`; its locked SHA-256 is still checked. Do not install frontend/backend or the app-controller chart separately with Helm.

To inspect the private Argo UI while the tunnel runs:

```sh
kubectl --context idea-board-test -n argocd port-forward svc/argocd-server 8443:443
```

Use authorized Secret access for the initial admin credential without logging or committing it; replace it after login. Stop the port-forward/tunnel when finished. The tunnel preserves cluster CA/hostname verification and does not change your default kubeconfig.

## First-time AWS account state setup

Skip this for the current test: its encrypted/versioned bucket, KMS key and OIDC provider already exist. Do not start a fresh local state for those existing resources.

For a new account, copy `apps/onboard/aws/state-bootstrap/terraform.tfvars.example` to a private `terraform.tfvars`, fill the account/region/unique bucket name, and enable GitHub OIDC creation only if the account has no provider yet. From that directory:

```sh
terraform init
terraform plan -out=reviewed.tfplan
terraform apply reviewed.tfplan
rm reviewed.tfplan
```

Migrate that initial local state into the new encrypted bucket before sharing ownership: copy its `backend.tf.example` to `backend.tf`, then run `terraform init -migrate-state` with the same bucket/encryption settings as above and a separate bootstrap key. Preserve the state backup until verified. State resources have destroy protection. Reuse the provider for app stacks.

## Provision GCP

GCP infrastructure is implemented and validated; live GCP app delivery and a second public URL are not yet verified. Use a separate project/state and private-network-connected administration for its private GKE API.

```sh
gcloud auth application-default login
cp apps/onboard/gcp/terraform.tfvars.example apps/onboard/gcp/terraform.tfvars
# Edit project, region, network ranges and administrator CIDRs.
cp apps/onboard/gcp/backend.tf.example apps/onboard/gcp/backend.tf
terraform -chdir=apps/onboard/gcp init \
  -backend-config="bucket=YOUR_EXISTING_VERSIONED_STATE_BUCKET" \
  -backend-config="prefix=idea-board/staging"
terraform -chdir=apps/onboard/gcp plan -out=reviewed.tfplan
terraform -chdir=apps/onboard/gcp apply reviewed.tfplan
rm apps/onboard/gcp/reviewed.tfplan
```

Configure a GCP image registry, GitOps target/Service settings and controller bootstrap before deploying an app there. Do not reuse AWS-specific image credentials, values or state.

## Pull-request checks

The [Terraform checks](.github/workflows/validate.yml) workflow runs only static checks: recursive formatting, TFLint, backend-disabled initialization, Terraform validation for AWS/GCP/state-bootstrap, and Python bootstrap syntax. It has read-only GitHub permissions, no cloud credentials, no live plan/apply and no app deployment.

```sh
make check  # Terraform 1.11.4 and TFLint 0.65.0 on PATH
make test   # optional local mock-provider regression tests; no cloud resources
```

AWS has seven mock-provider cases and GCP has four. Provider versions and module sources are locked. New module calls preserve the existing `module.aws[0]` and `module.gcp[0]` addresses; moving source files/repositories does not require a state migration. Existing AWS backend keys and private operator inputs were preserved locally; the original ignored files are archived in the app checkout's ignored artifacts until the operator no longer needs them.

## Migration verification

The existing AWS stack was checked from `apps/onboard/aws` against its live endpoint settings: Terraform reported zero resource changes and zero output changes. The old local public-endpoint CIDRs were stale; only the migrated ignored local copy was corrected to match the live restricted allowlist. No Terraform apply ran and endpoint access was not changed. The current cluster has both private access and a restricted public allowlist; the examples continue to default to private access.

All 11 mock-provider regression cases passed. Terraform formatting, TFLint and validation passed for AWS, GCP and account bootstrap. The moved private-access helper worked, and `bootstrap_argocd.py --check` verified the live account/target, cluster CA, database controls and Argo chart checksum without changing the cluster.
