# Terraform infrastructure

Reusable AWS and GCP modules, sourced by application roots that supply environment settings. This repository provisions cloud resources. Both cloud roots install Argo CD through Terraform's Helm provider.

| Repository | Responsibility |
| --- | --- |
| **terraform-infrastructure** — this private repository | Cloud resources, state configuration and the Argo controller for each cloud |
| [infra-helm-charts](https://github.com/surendarrajasekaran/infra-helm-charts#readme) | Helm values, parent/child Applications, app bootstrap and health/recovery |
| [om-idea-board](https://github.com/surendarrajasekaran/om-idea-board#readme) | App code, tests, image publishing and AI resource planning |

## Structure

```text
modules/
  aws/              VPC, EKS, PostgreSQL, ECR, publisher access and Argo CD
  gcp/              Network, GKE, PostgreSQL, GAR, publisher access and Argo CD
apps/onboard/
  aws/              AWS module calls, inputs, backend and Argo values
  gcp/              GCP module calls, inputs, backend and Argo values
```

Change reusable behavior in `modules/`; pass target-specific settings from `apps/onboard/`. PRs validate formatting, lint and syntax. Provisioning runs explicitly from an authorized operator machine.

## AWS database configuration

The AWS composition module sources separate `network`, `kubernetes`, `postgres`, `db-parameter-group`, `ecr` and `ci-registry-access` modules. The onboarding root also sources `argocd`. Resource settings flow from the root inputs into these modules.

Set database availability and storage in the AWS input file:

```hcl
database = {
  multi_az           = true
  storage_gb         = 20
  max_storage_gb     = 100
  backup_days        = 14
  log_retention_days = 14
}
```

Both the reference test inputs and example enable Multi-AZ. This setting is independent of EKS worker count and the environment's network HA settings. Production validation requires Multi-AZ; non-production inputs can explicitly set it to `false`. Multi-AZ adds a standby for failover and increases database cost; it does not provide automatic CPU/RAM scaling or a readable standby. Compute capacity remains controlled by `aws_database_instance_class`.

Storage autoscaling is configured from 20 GiB up to 100 GiB. Validation requires the maximum to be at least 110% of the initial allocation, keeping autoscaling enabled. Storage can grow to the cap; it does not automatically shrink. See [AWS storage autoscaling](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIOPS.Autoscaling.html) and [Multi-AZ DB instances](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZSingleStandby.html).

`modules/aws/db-parameter-group` creates a custom `postgres16` parameter group, which `postgres` attaches explicitly. Default parameter groups are rejected. TLS enforcement (`rds.force_ssl=1`) is fixed by the AWS composition module. Additional engine parameters can be passed from the onboarding root:

```hcl
database_parameters = {
  log_min_duration_statement = {
    value        = "1000"
    apply_method = "immediate"
  }
}
```

This example logs statements taking at least 1,000 milliseconds; it is optional and is not enabled in the reference inputs. Use `pending-reboot` for static parameters and review restart requirements before applying changes. A `moved` block maps the former inline parameter group to the new module address for existing Terraform states. Multi-AZ databases retain backups for at least 14 days; other database settings remain private, encrypted and deletion-protected by default.

After deployment, inspect the non-secret configuration summary:

```sh
terraform -chdir=apps/onboard/aws output database_configuration
```

## Prerequisites

Install Git, Terraform **1.11.4** and your cloud CLI. AWS needs AWS CLI v2 available to the Helm provider. GCP needs the Google Cloud CLI and `gke-gcloud-auth-plugin`. Install `kubectl` for the later GitOps bootstrap.

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

`apps/onboard/aws` sources `modules/aws/argocd`, which owns Helm release `argocd` in namespace `argocd`. The provider receives the EKS endpoint/CA directly from module outputs and uses `aws eks get-token` for short-lived authentication. It does not perform a separate cluster lookup that can block teardown after the cluster is gone. No separate Argo installer or manual Helm install is needed.

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

`apps/onboard/gcp` sources the GCP composition module and its separate `network`, `kubernetes`, `postgres`, `gar` and `ci-registry-access` modules. It also installs Argo CD using `modules/gcp/argocd`. Cloud provisioning remains an operator task; the existing application release workflow still targets AWS and must be extended before automated GCP application delivery. No live GCP deployment or public URL has been verified.

| Component | GCP configuration |
| --- | --- |
| Networking | Custom VPC, private nodes, secondary pod/service ranges, Private Google Access, Cloud NAT and private service access for SQL |
| Kubernetes | Regional GKE Autopilot, managed node provisioning and resource metrics, Dataplane V2 network policy, custom node identity and restricted API access |
| Registry | Separate private frontend/backend Docker repositories in Google Artifact Registry; immutable tags and cleanup preview |
| Image access | Repository-scoped reader for the GKE node identity; separate repository-scoped writer for GitHub |
| GitHub authentication | Workload Identity Federation restricted to numeric owner/repository IDs, exact environment subject and branch; no service-account key |
| Database | PostgreSQL 16 Enterprise, private IP, encrypted connections, regional standby by default, PITR, backups and capped SSD storage growth |
| Argo CD | Terraform-managed Helm release with digest-pinned controller/Redis images and a private ClusterIP service |

Cloud SQL has instance `database_flags`, rather than an AWS-style parameter-group resource. Set them through `database_flags` in the onboarding inputs. `database.high_availability` controls `REGIONAL` versus `ZONAL` independently of the environment; production requires regional availability. The regional default uses `db-custom-2-7680`; set `gcp_database_tier` for another supported size. Compute sizing is explicit, while disk autoscaling grows from 20 GB to a 100 GB cap. Validation reserves room for at least one SSD autogrowth increment. PITR keeps seven days of transaction logs; regional instances keep at least 14 daily backups, with retained backups enabled on deletion. Cloud SQL is encrypted at rest by Google and requires TLS in transit. The existing app connection format uses `verify-ca` with the per-instance CA mounted from a Secret. These settings do not implement automatic database compute scaling.

VPC flow logs and Cloud NAT error logs provide network evidence. Cloud SQL logs use the project's Cloud Logging retention policy; the unused GCP `database.log_retention_days` input was removed because it never configured that policy. Review optional slow-query flags for application data exposure and cost. Existing GCP stacks retain their resource addresses; review regional-HA, new APIs, IAM, GAR and Argo changes before applying.

### Configure the target

Use an existing billing-enabled project, a versioned and access-controlled GCS state bucket, and an operator authorized to manage the required APIs, networking, GKE, SQL, GAR and IAM. The bucket must exist before initialization. Terraform enables Artifact Registry, IAM Credentials and STS APIs alongside the existing platform APIs; API services remain enabled on stack deletion.

```sh
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
# Install gke-gcloud-auth-plugin with your Google Cloud CLI/package manager.
gke-gcloud-auth-plugin --version

cp apps/onboard/gcp/terraform.tfvars.example apps/onboard/gcp/terraform.tfvars
mkdir -p artifacts/gcp
cp apps/onboard/gcp/backend.hcl.example artifacts/gcp/backend.hcl
# Edit project, region, administrator CIDRs, database sizing and backend location.
# Edit github.repository, repository_id and owner_id; set github = null to omit CI.
```

Find the GitHub numeric IDs using your authorized personal account:

```sh
gh api repos/YOUR_OWNER/YOUR_APP_REPO --jq '{repository_id: .id, owner_id: .owner.id}'
```

The expected publishing environment is `gcp-<environment>`, for example `gcp-test`. The default subject is `repo:OWNER/REPO:environment:gcp-test`. If your repository uses customized immutable-ID OIDC subjects, set `github.subject_prefix` to the exact matching `repo:OWNER@OWNER_ID/REPO@REPOSITORY_ID`. The provider also checks the immutable numeric IDs and `refs/heads/<branch>`, so a pull request or another repository cannot use this publishing identity. GKE nodes get pull access to all this target's GAR repositories. The publisher can write only frontend/backend repositories and receives no GKE, SQL, infrastructure or other-repository permissions. See [Google's federation guidance](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines) and [GKE node service accounts](https://docs.cloud.google.com/kubernetes-engine/security/configure-node-service-accounts).

### Provision infrastructure, then Argo CD

Terraform's Helm provider uses the created GKE endpoint/CA directly and `gke-gcloud-auth-plugin --use_application_default_credentials` for short-lived access. The operator needs cluster-admin permissions for the Argo Helm installation and network access to the selected API endpoint. The default private endpoint needs a VPN/private runner route; enabling the public endpoint requires real public administrator CIDRs. The example documentation CIDR is not deployable access.

From the repository root, use Terraform **1.11.4**, rather than an older system binary:

```sh
terraform -chdir=apps/onboard/gcp init -reconfigure \
  -backend-config="$PWD/artifacts/gcp/backend.hcl"

# Fresh cluster: provision platform resources before the Helm provider connects.
terraform -chdir=apps/onboard/gcp plan -var-file=terraform.tfvars \
  -target=module.gcp -out=infra.tfplan
# Review the saved plan, including project, IAM and regional database cost.
terraform -chdir=apps/onboard/gcp apply infra.tfplan

# Establish approved connectivity to the new GKE API, then install Argo.
terraform -chdir=apps/onboard/gcp plan -var-file=terraform.tfvars -out=full.tfplan
terraform -chdir=apps/onboard/gcp apply full.tfplan
rm apps/onboard/gcp/infra.tfplan apps/onboard/gcp/full.tfplan

PROJECT_ID="$(terraform -chdir=apps/onboard/gcp output -raw gcp_project)"
REGION="$(terraform -chdir=apps/onboard/gcp output -raw region)"
CLUSTER_NAME="$(terraform -chdir=apps/onboard/gcp output -raw cluster_name)"
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --region "$REGION" --project "$PROJECT_ID" --internal-ip
kubectl -n argocd get deployments
kubectl top nodes
terraform -chdir=apps/onboard/gcp output repository_urls
terraform -chdir=apps/onboard/gcp output database_configuration
```

`--internal-ip` uses the private route. If you explicitly configured public API access, use `get-credentials` without that flag. The plugin used by Terraform reads Application Default Credentials, which can differ from the active `gcloud` account; authenticate both as intended. Use targeting only for the first platform phase. Existing-stack changes use a full reviewed plan. GKE Autopilot supplies node provisioning and the resource-metrics API, so a separate EKS Metrics Server add-on is unnecessary.

### Registry and application handoff

`repository_urls` returns image prefixes such as `REGION-docker.pkg.dev/PROJECT/idea-board-test-frontend/frontend` and the equivalent backend path. The images themselves are built and pushed by application CI; creating a repository does not populate it.

| Terraform output | Consumer |
| --- | --- |
| `registry_host`, `repository_urls` | Docker login, build/push destinations and GitOps image values |
| `workload_identity_provider` | GitHub Google authentication provider input |
| `publisher_service_account_email` | GitHub Google authentication service-account input |
| `node_service_account_email` | Verify GKE image-pull identity and repository reader bindings |
| `database_url`, `migration_database_url`, `application_password` | Sensitive runtime/migration Secret values |
| `database_ca_certificate` | Sensitive output containing the SQL CA to mount at `/etc/postgresql/ca/ca.crt` |
| `database_egress_cidrs` | GCP-target backend network-policy destination ranges |

For GitHub publishing, configure a `gcp-test` environment and give its authentication job `id-token: write` with read-only repository contents. Use the WIF provider and publisher outputs with Google's authentication action, then Docker login as `oauth2accesstoken` using the short-lived access token. Do not create or store a Google service-account JSON key. Add a GCP publishing path to the app workflow and a separate GCP target in `infra-helm-charts` before expecting an end-to-end deployment: GCP image prefixes, frontend LoadBalancer settings, namespace/project/controller values, database Secret/CA references, release target and health URL must belong to that target. Do not overwrite AWS values or reuse AWS recovery history. Terraform installs the controller; the GitOps parent Application must create the two service Applications.

GAR cleanup is a dry run by default. Review candidates before setting `gar_cleanup_dry_run = false`: only old untagged artifacts are eligible, and the 20 most recent versions per package are retained. Immutable tagged images stay available for rollback; their retained storage still costs money. Additional GAR services, such as an operator-managed Argo mirror, get node pull access but are excluded from the application publisher's write permissions.

For removal, retire the GCP Applications and LoadBalancer Services while the cluster is reachable. Remove the Terraform-managed Argo release before GKE, disable database protections through a reviewed apply, and review SQL backup retention and GAR contents before destroy. The remote-state bucket belongs to a separate lifecycle and is not destroyed by this root.

## Remove an AWS target

Disable its application release and GitOps health workflows before decommissioning. While Kubernetes is reachable, remove the application Services/workloads and wait for their cloud load balancers to disappear. Uninstall the Terraform-managed Argo release before removing the cluster; a full Terraform destroy orders that dependency through the cluster module outputs.

Disable database deletion protection through a reviewed configuration apply and empty only this target's ECR repositories before destroying them. Save and review a destroy plan for the same backend and inputs used to provision the target. The database configuration creates a final snapshot; review retained snapshots and automated backups separately when completing cleanup.

If a previous partial destroy already removed EKS, check the remaining Terraform state and cloud resources first. An orphaned Kubernetes load balancer may still need deletion through the cloud API. Back up state before any state repair; removing an address from state does not delete its real resource. State storage and shared identity providers have a separate lifecycle from the application stack.

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

Renew expired cloud logins before operating. If Argo installation times out, verify the selected cluster API reachability, cloud authentication and image access. Backend-disabled validation is for configuration checks; initialize the real backend again before provisioning.

## Kubernetes availability and resource metrics

AWS node-pool defaults and the supplied test inputs use a minimum and desired count of two workers, with a maximum of three. The EKS module installs `metrics-server` as an AWS community add-on after compute is available. AWS selects a compatible add-on version using the same EKS module mechanism as the existing add-ons. Its serving port 10251 is reachable from the control-plane security group; node traffic already permits kubelet metric collection on 10250. This adds no publicly exposed metrics port and does not disable kubelet TLS verification in our Terraform configuration. See [EKS Metrics Server](https://docs.aws.amazon.com/eks/latest/userguide/metrics-server.html).

The GitOps repository owns the two service HPAs, each initially 2–4 replicas at 70% CPU utilization, pod anti-affinity, topology spreading and PDBs. Terraform owns the cluster, workers and Metrics Server. The worker-group maximum does not enable automatic node growth: no Cluster Autoscaler or Karpenter is installed. HPA scales pods within current cluster capacity. Two nodes increase the baseline cost; node/zone placement and capacity must be verified after apply. A two-node group spanning two subnet AZs does not guarantee one node per AZ. GKE Autopilot manages node provisioning and resource metrics independently; this AWS add-on is not installed there.

After apply, verify resource metrics before expecting the GitOps HPAs to work:

```sh
kubectl -n kube-system rollout status deployment/metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl get nodes -L topology.kubernetes.io/zone
```

Continue with the [GitOps availability checks](https://github.com/surendarrajasekaran/infra-helm-charts#availability-and-autoscaling). The current test stack was deleted; changing these files alone does not recreate it or prove live scaling.
