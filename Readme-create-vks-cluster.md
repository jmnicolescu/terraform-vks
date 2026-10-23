<!--
author: "Julius M. Nicolescu"
date: "October 2026"
description: "Technical guide to deploying and managing DEV and QA VKS clusters on an existing VMware Cloud Foundation Supervisor with Terraform, including cluster topology, provider configuration, readiness verification, Kubernetes upgrades, worker scaling, and captured deployment outputs."
keywords: ["VCF", "Supervisor", "VKS", "Kubernetes", "Terraform", "Cluster deployment", "Cluster lifecycle"]
lang: en
-->

# Create VKS clusters with Terraform

This workflow creates **two VKS clusters** on an existing Supervisor using one shared Terraform module. Each cluster has its own configuration, provider lock file, saved plan and Terraform state. Run the procedure for both directories to create both clusters.

**Target VCF release:** `9.1.1.0-545627-2026-09`.

| Setting | DEV | QA |
| --- | --- | --- |
| Terraform directory | `dev-cluster-01` | `qa-cluster-02` |
| Cluster name | `dev-cluster-01` | `qa-cluster-02` |
| Supervisor namespace | `dev-namespace` | `qa-namespace` |
| Control-plane nodes | 3 | 3 |
| Worker nodes | 3 | 3 |
| Containerd volume per worker | `30Gi` | `30Gi` |

These are desired settings from the configuration reviewed on 2026-10-22, not live deployment status. The QA directory and Cluster are both named `qa-cluster-02`.

## GitHub repository

**Repository:** [github.com/jmnicolescu/terraform-vks](https://github.com/jmnicolescu/terraform-vks)

Access the Terraform projects, deployment guides, and captured output files in this repository.

## Contents

- [Requirements: Supervisor connection](#requirements-supervisor-connection)
- [GitHub repository](#github-repository)
- [Prerequisites](#prerequisites)
- [Files and configuration](#files-and-configuration)
- [Providers and design decisions](#providers-and-design-decisions)
- [Create both clusters](#create-both-clusters)
- [Connect to the VKS clusters](#connect-to-the-vks-clusters)
- [Generated files and outputs](#generated-files-and-outputs)
- [Upgrade and capacity management](#upgrade-and-capacity-management)
- [Adopt an existing cluster](#adopt-an-existing-cluster)
- [Delete a cluster](#delete-a-cluster)
- [API behavior and troubleshooting](#api-behavior-and-troubleshooting)
- [Output](#output)
- [References](#references)

| Operation | Configuration or command | Completion criterion |
| --- | --- | --- |
| Create DEV and QA | Plan and apply each root separately | Both workload APIs accessible; each cluster has 3 ready control-plane nodes and 3 ready workers |
| Upgrade Kubernetes | Change `kubernetes_version`, then plan and apply each root | Supported target release reconciled; all nodes ready at the target version; workloads healthy |
| Scale workers | Change `worker_count` from `3` to `5` in each root | Each cluster has 3 ready control-plane nodes and 5 ready workers |
| Upgrade Terraform providers | Deliberately run `init -upgrade` in each root | Reviewed lock-file changes, successful validation and reviewed plans |

## Requirements: Supervisor connection

<p style="color: red;"><strong>IMPORTANT: An active network connection to the Supervisor API is required. Before running the deployment workflow, the supervisor context must exist, be available, and authenticate successfully to the intended Supervisor.</strong></p>

### Check the requirements

- Have an existing, operational Supervisor and network access to its API endpoint.
- Install Bash, VCF CLI (`vcf`), and `kubectl`, and make them available in `PATH`.
- Have valid vSphere SSO credentials with permission to access the Supervisor and perform the checks below.
- Use the Terraform version, providers, permissions, and platform resources required by the selected project. Namespace roots require Terraform >= 1.10; VKS roots require Terraform >= 1.5.

### Create or activate the Supervisor context

From the **repository root**, check whether the context already exists:

```bash
vcf context list
kubectl config get-contexts supervisor
```

If the `supervisor` context does not exist, review and modify [utilities/01-create-supervisor-context.sh](https://github.com/jmnicolescu/terraform-vks/blob/main/utilities/01-create-supervisor-context.sh) for your environment before running it:

| Script setting | What to review or change |
| --- | --- |
| `SUPERVISOR_API_ENDPOINT` | Set the intended Supervisor API address, reachable from this workstation. |
| `VCF_CLI_VSPHERE_USERNAME` | Set the vSphere SSO account authorized to access that Supervisor. |
| `VCF_CLI_VSPHERE_PASSWORD` | Review the credential handling. The current script assigns this variable but does not export it or pass it to `vcf`; do not assume that changing it supplies the CLI password. Complete authentication when prompted, and do not commit credentials. |
| `CONTEXT_NAME` | Keep `supervisor` to match the VKS Terraform roots, or update their `supervisor_context` settings and the verification commands consistently. |

The script checks for `vcf` and `kubectl`, attempts to delete the existing local context named `supervisor`, creates it with the configured endpoint and SSO username, activates it, lists VCF contexts, and runs `kubectl get nodes`. It changes local connection configuration; it does not create the Supervisor infrastructure or deploy namespaces or VKS clusters. Context creation currently uses `--insecure-skip-tls-verify`; review that lab TLS setting before use.

Run the reviewed script from the repository root:

```bash
bash utilities/01-create-supervisor-context.sh
```

If the context already exists and points to the correct Supervisor, activate it without recreating it:

```bash
vcf context use supervisor
```

### Verify the connection before proceeding

```bash
vcf context list
kubectl config get-contexts supervisor
kubectl config use-context supervisor
kubectl get nodes
```

**Proceed only when `supervisor` points to the intended endpoint and the explicit node query succeeds.** The script currently continues after command failures and prints its final `SUCCESS` message unconditionally; that message alone does not prove connectivity. If authentication fails, refresh the Supervisor login. If the endpoint is unreachable, restore network/VPN access and check the configured address. If access is forbidden, resolve the account permissions before continuing.

The VKS Terraform roots use the authenticated `supervisor` context from `~/.kube/config` by default and require live Supervisor access for planning and applying. The namespace Terraform providers authenticate separately to vCenter; this Supervisor connection requirement prepares the documented workflow and Kubernetes verification, while their vCenter connection remains independently required.

## Prerequisites

- Terraform >= 1.5 and kubectl. Both roots require `hashicorp/kubernetes ~> 3.0` and `hashicorp/local ~> 2.5`; their lock files select versions `3.4.0` and `2.9.1`, respectively.
- An existing Supervisor with VKS controllers and the `cluster.x-k8s.io/v1beta2` Cluster CRD. Planning and applying both require access to the Supervisor API.
- An authenticated kubeconfig. Both configurations default to `~/.kube/config` and the explicit context `supervisor`; verify the endpoint and TLS settings before use.
- Existing `dev-namespace` and `qa-namespace`, with the required VM/storage class assignments, compatible release and ClusterClass, network configuration and sufficient quota for both clusters.
- API discovery and Cluster read/create/patch/delete permissions in both namespaces. Exact platform role requirements have not been verified.
- Optional additional CA trust: both roots currently set `additional_trusted_cas = []`. If you enable the commented example, create `harbor-user-trusted-ca-secret` with key `harbor-ca` in each affected namespace first. Terraform references these Secrets; it does not create them.

## Files and configuration

This README is in the repository root, alongside `terraform-create-vks-cluster/`:

```text
terraform-create-vks-cluster/
├── dev-cluster-01/
│   ├── main.tf
│   └── .terraform.lock.hcl
├── qa-cluster-02/
│   ├── main.tf
│   └── .terraform.lock.hcl
└── modules/vks-cluster/
    ├── main.tf
    ├── variables.tf
    ├── versions.tf
    └── outputs.tf
```

Edit deployment settings in [DEV main.tf](terraform-create-vks-cluster/dev-cluster-01/main.tf) and [QA main.tf](terraform-create-vks-cluster/qa-cluster-02/main.tf). Terraform reads these root settings directly; it does not source the original lab configuration file `00-vcf9-env.sh` or use the generated YAML manifests as inputs.

Both roots currently use:

| Input | Configured value |
| --- | --- |
| `kubernetes_version` | `v1.35.6---vmware.2-vkr.3` |
| `cluster_class` | `builtin-generic-v3.7.0` |
| `cluster_class_namespace` | `vmware-system-vks-public` |
| `vm_class` | `best-effort-medium` |
| `storage_class` | `vsan-default-storage-policy` |
| `pod_cidrs` | `["10.95.0.0/16"]` |
| `service_cidrs` | `["10.96.0.0/12"]` |
| `containerd_volume_capacity` | `30Gi`, mounted at `/var/lib/containerd` |

Confirm the CIDRs fit the network design for each cluster. The module validates CIDR syntax, not overlap or platform compatibility. Three workers request 90 GiB of containerd storage per cluster, excluding operating-system disks and other storage.

Each root calls `../modules/vks-cluster` and passes its configured `kubernetes.supervisor` provider to the module. The kubeconfig supplies authentication and the API endpoint. The shared module builds one Cluster object with Antrea, Photon OS annotations, certificate rotation, pod security settings and one worker pool named `<cluster-name>-np01`.

See [variables.tf](terraform-create-vks-cluster/modules/vks-cluster/variables.tf) for all inputs and validation. Changes to the shared module affect future plans for both clusters; applying one root operates only on that root's state. Never copy state or saved plans between directories.

## Providers and design decisions

### Provider selection and version control

| Provider | Constraint / selected version | Responsibility |
| --- | --- | --- |
| `hashicorp/kubernetes` | `~> 3.0` / `3.4.0` | Applies the VKS Cluster custom resource to the Supervisor through `kubernetes_manifest` |
| `hashicorp/local` | `~> 2.5` / `2.9.1` | Writes the desired Cluster YAML through `local_file` |

The selected versions above come from both local `.terraform.lock.hcl` files, reviewed on 2026-10-22. They describe this checkout, not a claim that these are the latest available versions. The constraints allow compatible releases below the next major version; the lock files preserve the exact selections and checksums. Keep the lock files with the configuration. Routine `terraform init` reuses those selections; `init -upgrade` deliberately reselects providers within the constraints. See HashiCorp's [dependency lock-file documentation](https://developer.hashicorp.com/terraform/language/files/dependency-lock) and [init reference](https://developer.hashicorp.com/terraform/cli/commands/init).

The Kubernetes provider is appropriate because this workflow manages a Kubernetes custom resource exposed by the Supervisor. VKS controllers turn its topology into virtual machines and workload nodes. No vSphere or VCF Automation Terraform provider is configured here. The root's `kubernetes.supervisor` alias supplies an explicit kubeconfig context to the shared module, preventing reliance on whichever context happens to be active in the shell.

`kubernetes_manifest` needs the resource schema during planning. The Supervisor, VKS service and Cluster CRD must therefore exist before running this workflow. They cannot be bootstrapped by these roots. See HashiCorp's [custom-resource workflow](https://developer.hashicorp.com/terraform/tutorials/kubernetes/kubernetes-provider).

### Architecture and operational tradeoffs

| Decision in the implementation | Rationale and operational consequence |
| --- | --- |
| One shared module, two independent roots | Keeps the manifest structure consistent while allowing separate plans, state and change windows. Shared-module edits must be reviewed against both roots. |
| Local state; no backend block | Simple for this lab, but state must be protected and backed up. Serialize operations on each root. A team workflow should deliberately configure a backend with access control, locking and recovery before concurrent use. |
| One Cluster resource per root | VKS owns derived Machines and infrastructure. Change the Cluster topology through Terraform rather than editing generated Machines or MachineDeployments. |
| Three control-plane nodes and one worker pool | Separates control-plane capacity from the independently configurable worker count. This module does not model multiple worker pools or availability-zone placement. |
| Explicit release, ClusterClass, VM class and storage class | Makes desired settings reviewable. Input validation does not establish installed-platform compatibility or available capacity. |
| Server-side field manager `terraform-vks-cluster`, `force_conflicts = false` | Field-ownership conflicts stop the apply instead of forcibly taking fields from another manager. Investigate the competing owner before changing ownership. |
| Computed annotations, labels, topology variables and version | Accommodates Supervisor admission defaults and release normalization. Compare the requested values with the reconciled object: computed fields permit server-returned differences and are not a readiness check. |
| Explicit pod-security and certificate settings | Current policy audits at `restricted` and enforces/warns at `privileged`, with `deactivated = false`; it does not enforce the restricted profile. Certificate rotation is enabled with a 90-day renewal lead time. Review these choices against workload requirements. |
| Antrea and Photon OS selection | Preserves the lab topology; this module does not expose a general CNI or operating-system selector. |
| Separate `30Gi` containerd volume on each worker | Keeps container image/runtime storage configurable independently of worker count. Changing volume capacity is a separate lifecycle operation requiring platform validation. |
| Optional CA Secret references | Allows additional trust without embedding certificate contents in Terraform configuration. Secrets remain externally managed. |
| Generated YAML from the same desired manifest | Provides a readable deployment artifact without maintaining a second manifest definition. It is neither a backup of live status nor an independent deployment owner. |

The field-management and computed-field behavior is described in the official [`kubernetes_manifest` reference](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest). Local artifact behavior is documented in the [`local_file` reference](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file). Registry links may show newer documentation than the locally locked versions; select the matching version when checking version-specific behavior.

## Create both clusters

### 1. Prepare and check the Supervisor

Start each command block containing a `cd terraform-create-vks-cluster/...` command from the repository root (`terraform-vks/`). Enter the selected cluster directory before running Terraform. Blocks without a `cd` continue in the directory selected by the preceding block. When starting a different procedure, return to the repository root (`terraform-vks/`) first.

```bash
umask 077
kubectl config get-contexts
kubectl config use-context supervisor
kubectl get namespaces dev-namespace qa-namespace
kubectl get crd clusters.cluster.x-k8s.io
```

If you configure a different kubeconfig or Supervisor context in either root, use the same connection for its kubectl checks. If enabling additional CA trust, select the Supervisor context and check the referenced Secret in both namespaces:

```bash
kubectl config use-context supervisor
kubectl -n dev-namespace get secret harbor-user-trusted-ca-secret
kubectl -n qa-namespace get secret harbor-user-trusted-ca-secret
```

Do not run the Bash deployment scripts as Terraform prerequisites: they submit infrastructure changes themselves. If either Cluster already exists outside its Terraform state, follow [Adopt an existing cluster](#adopt-an-existing-cluster) before planning.

### 2. Create DEV VKS cluster

```bash
cd terraform-create-vks-cluster/dev-cluster-01
terraform init
terraform validate
terraform plan -out=vks.tfplan
```

Review the plan. For a fresh deployment, it should create `dev-namespace/dev-cluster-01` and its local YAML file. Confirm three control-plane nodes and three workers, then apply the saved plan:

```bash
terraform apply vks.tfplan
```

### 3. Create QA VKS cluster

Complete the DEV readiness checks in the next section before proceeding to QA. Return to the repository root (`terraform-vks/`) before the following block.

```bash
cd terraform-create-vks-cluster/qa-cluster-02
terraform init
terraform validate
terraform plan -out=vks.tfplan
```

Review the plan. For a fresh deployment, it should create `qa-namespace/qa-cluster-02` and its local YAML file. Confirm three control-plane nodes and three workers, then apply the saved plan:

```bash
terraform apply vks.tfplan
```

Each saved-plan apply executes the reviewed plan without a further approval prompt. Generate a fresh plan after changing configuration. Protect state and plan files, and retain both provider lock files.

### 4. Verify both clusters

Successful apply means Terraform applied the Cluster object. The module does **not** wait for workload readiness; Supervisor controllers provision the infrastructure asynchronously.

```bash
kubectl config use-context supervisor
kubectl -n dev-namespace get clusters.cluster.x-k8s.io dev-cluster-01 -o yaml
kubectl -n dev-namespace get machines.cluster.x-k8s.io -l cluster.x-k8s.io/cluster-name=dev-cluster-01

kubectl -n qa-namespace get clusters.cluster.x-k8s.io qa-cluster-02 -o yaml
kubectl -n qa-namespace get machines.cluster.x-k8s.io -l cluster.x-k8s.io/cluster-name=qa-cluster-02
```

For each cluster, confirm current `Available=True` conditions, three ready control-plane nodes and three ready workers. Follow [Connect to the VKS clusters](#connect-to-the-vks-clusters) to establish each workload context and verify API access and node readiness. Object existence and generated YAML alone do not establish readiness.

## Connect to the VKS clusters

After the Supervisor reports the target cluster as available, create its local access context and verify the workload API. Complete the DEV procedure for `dev-cluster-01` and the QA procedure for `qa-cluster-02` independently. Run the following scripts from the **repository root (`terraform-vks/`)**, not from a Terraform deployment directory.

### Connection requirements

<p style="color: red;"><strong>IMPORTANT: Maintain an active network connection to the Supervisor before running either context script. The workstation must also be able to reach the selected workload cluster API to use kubectl after authentication.</strong></p>

Bash, VCF CLI (`vcf`), and `kubectl` must be available in `PATH`. First establish and verify Supervisor access using [Requirements: Supervisor connection](#requirements-supervisor-connection). Use a vSphere SSO account authorized to access the target workload cluster.

Review the selected script before running it. Set `SUPERVISOR_API_ENDPOINT` to the Supervisor address and `VCF_CLI_VSPHERE_USERNAME` to the intended SSO account. Verify the namespace and cluster settings against the table below.

| Environment | Script | `CLUSTER_NAMESPACE` | `CLUSTER_NAME` | Context activated by the script |
| --- | --- | --- | --- | --- |
| DEV | [02-create-dev-cluster-01-context.sh](https://github.com/jmnicolescu/terraform-vks/blob/main/utilities/02-create-dev-cluster-01-context.sh) | `dev-namespace` | `dev-cluster-01` | `dev-cluster-01:dev-cluster-01` |
| QA | [03-create-qa-cluster-02-context.sh](https://github.com/jmnicolescu/terraform-vks/blob/main/utilities/03-create-qa-cluster-02-context.sh) | `qa-namespace` | `qa-cluster-02` | `qa-cluster-02:qa-cluster-02` |

Both scripts currently use `--insecure-skip-tls-verify`; review this lab TLS setting for your environment. They assign `VCF_CLI_VSPHERE_PASSWORD` locally but do not export it or pass it to the CLI. Complete authentication when prompted; do not assume the assignment supplies the password, and do not commit credentials.

### What the context scripts do

Each script performs the same sequence for its configured cluster:

1. Checks that `vcf` and `kubectl` are installed and available in `PATH`.
2. Attempts to delete the existing local VCF context named after the cluster, then creates it again. Re-running a script therefore recreates that local access configuration.
3. Calls `vcf context create` with the Supervisor endpoint, SSO username, workload namespace, and workload cluster name, using Kubernetes/basic authentication.
4. Activates the workload context using `vcf context use` with the `cluster-name:cluster-name` identifier shown above.
5. Lists the VCF contexts and runs `kubectl get nodes` against the active Kubernetes context.

These utilities configure local access to existing clusters. They do not create, scale, or delete VKS clusters, and they do not modify Terraform state. Activating a workload context changes the destination of subsequent `kubectl` commands.

### Connect to DEV: dev-cluster-01

From the repository root, create and activate the DEV context:

```bash
bash utilities/02-create-dev-cluster-01-context.sh
```

Confirm the selected context, then query DEV explicitly:

```bash
vcf context list
kubectl config current-context
kubectl config use-context dev-cluster-01:dev-cluster-01
kubectl get nodes -o wide
kubectl get pods -A
```

The active context should be `dev-cluster-01:dev-cluster-01`. For the supplied three-control-plane, three-worker configuration, verify that all six nodes report `Ready`. Review pod status and investigate unexpected pending, failed, or restarting workloads.

### Connect to QA: qa-cluster-02

From the repository root, create and activate the QA context:

```bash
bash utilities/03-create-qa-cluster-02-context.sh
```

Confirm the selected context, then query QA explicitly:

```bash
vcf context list
kubectl config current-context
kubectl config use-context qa-cluster-02:qa-cluster-02
kubectl get nodes -o wide
kubectl get pods -A
```

The active context should be `qa-cluster-02:qa-cluster-02`. For the supplied configuration, verify that all six nodes report `Ready` and review pod status. QA becomes the active context after this procedure; select the matching context with `kubectl config use-context` before checking each cluster.

### Switch between existing contexts

Once the contexts exist, activate the required target with the corresponding command:

| Target | Command |
| --- | --- |
| DEV workload cluster | `vcf context use dev-cluster-01:dev-cluster-01` |
| QA workload cluster | `vcf context use qa-cluster-02:qa-cluster-02` |
| Supervisor | `vcf context use supervisor` |

Use the Supervisor context for Cluster and Machine resource checks, and the workload context for that cluster's nodes, pods, and applications. The Terraform roots continue to use their explicitly configured Supervisor context.

**Connection success requires a successful query against the intended workload context.** Both scripts currently continue after command failures and print a final `SUCCESS` message unconditionally. If a script reports an error, inspect the context and explicit node-query results before proceeding. Resolve authentication, endpoint reachability, or access permissions as indicated by the error; if provisioning is incomplete, return to the Supervisor readiness checks.

## Generated files and outputs

Each root exposes `cluster_name`, `namespace`, `manifest_yaml` and `manifest_file`. Apply writes the desired manifest automatically:

```text
dev-cluster-01/output-YYYY-MM-DD/create-dev-cluster-01.yaml
qa-cluster-02/output-YYYY-MM-DD/create-qa-cluster-02.yaml
```

The date is the plan's UTC date. Files use permission `0600`, and newly created output directories use `0700`. The YAML contains desired configuration and CA Secret references, without runtime status or Secret contents.

From the repository root (`terraform-vks/`), inspect each path in its own cluster directory:

```bash
cd terraform-create-vks-cluster/dev-cluster-01
terraform output -raw manifest_file
cd ../qa-cluster-02
terraform output -raw manifest_file
```

Terraform manages one current YAML file per root. A later plan with a different date can replace it, and destroy removes the tracked file. These directories are not permanent archives. Keep one lifecycle owner per Cluster; do not independently apply generated YAML to a Terraform-managed Cluster.

## Upgrade and capacity management

A Kubernetes release upgrade, worker scaling and a Terraform provider upgrade are different changes. Plan them separately so that each result can be verified. Start each procedure from the repository root (`terraform-vks/`), enter the selected cluster directory as shown, and use its existing state. Apply-only blocks continue in the directory used to create the plan.

### 1. Prepare a change window

Before either a release upgrade or scaling:

1. Confirm both clusters are healthy using the Supervisor and workload checks below. Resolve existing reconciliation failures first.
2. Preserve the current root configuration, shared module and lock files. Back up each existing state with restricted permissions; Terraform state recovery does not restore Kubernetes workloads or persistent-volume data.
3. Confirm application and persistent-data backups and their restore procedure. For upgrades, check add-on compatibility, deprecated APIs, PodDisruptionBudgets and workloads that cannot tolerate node drain or replacement.
4. Check namespace quotas, VM/storage class availability, IP capacity and datastore/compute capacity. Reserve temporary capacity for rolling node replacement in addition to final node counts; the required surge depends on the installed VKS configuration.
5. Change DEV first. Proceed to QA only after DEV satisfies the completion criteria. Use a fresh plan for each root and each operation.

Example state snapshots for already managed clusters:

```bash
cd terraform-create-vks-cluster/dev-cluster-01
umask 077
CHANGE_TIME=$(date -u +%Y-%m-%d-%H-%M-%S)
mkdir -m 700 "state-backup-${CHANGE_TIME}"
terraform state pull > "state-backup-${CHANGE_TIME}/dev.tfstate"

cd ../qa-cluster-02
mkdir -m 700 "state-backup-${CHANGE_TIME}"
terraform state pull > "state-backup-${CHANGE_TIME}/qa.tfstate"
```

Check each command succeeds and the snapshots are nonempty. Keep these files private and outside version control. Never restore or push an older state merely to undo an infrastructure change.

### 2. Upgrade the Kubernetes release

The current configured release is `v1.35.6---vmware.2-vkr.3`. No next release is prescribed here: select an exact release available to this Supervisor and supported from the current release by the installed VKS service. Confirm its OS image availability, upgrade path and compatible ClusterClass before editing. Do not infer compatibility from version ordering or assume that skipping minor versions is supported.

Broadcom documents the [VKS release upgrade workflow](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/update-a-tanzu-kubernetes-cluster-by-upgrading-the-kubernetes-version.html) and [versioned ClusterClass updates](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/updating-tkg-service-clusters/updating-the-versioned-clusterclass.html). These VCF 9.0 references provide platform background; confirm the installed VCF 9.1.1/VKS release's requirements. This module uses `cluster.x-k8s.io/v1beta2` and `spec.topology.classRef`; do not copy legacy v1alpha3 field paths into it.

Inspect the current objects and discover the release resources exposed by the Supervisor:

```bash
kubectl config use-context supervisor
kubectl api-resources
kubectl -n vmware-system-vks-public get clusterclasses.cluster.x-k8s.io
kubectl -n dev-namespace get clusters.cluster.x-k8s.io dev-cluster-01 -o yaml
kubectl -n qa-namespace get clusters.cluster.x-k8s.io qa-cluster-02 -o yaml
```

Use the discovered release resource and installed VKS documentation to inspect candidate release compatibility. A release being listed does not establish that it is a valid upgrade target for either cluster.

In [DEV main.tf](terraform-create-vks-cluster/dev-cluster-01/main.tf), change `kubernetes_version` to the verified target identifier. Update `cluster_class` only if required by the supported target combination. Leave worker count and unrelated settings unchanged. The module maps these inputs to `spec.topology.version` and `spec.topology.classRef.name`.

```bash
cd terraform-create-vks-cluster/dev-cluster-01
terraform validate
terraform plan -out=upgrade.tfplan
terraform show -no-color upgrade.tfplan
```

Review for an in-place update to the existing Cluster with the intended release and any explicitly required ClusterClass change. A generated `local_file` change is expected. Stop if the Cluster is to be destroyed or replaced, its identity changes, or unrelated topology changes appear. The Cluster resource staying in place does not mean its nodes stay in place: VKS performs the node rollout.

Apply only the reviewed plan:

```bash
terraform apply upgrade.tfplan
```

Verify DEV with [completion checks](#4-verify-completion) before changing QA. Then set the verified target in [QA main.tf](terraform-create-vks-cluster/qa-cluster-02/main.tf), return to the repository root (`terraform-vks/`), and repeat:

```bash
cd terraform-create-vks-cluster/qa-cluster-02
terraform validate
terraform plan -out=upgrade.tfplan
terraform show -no-color upgrade.tfplan
# Run only after reviewing the QA plan.
terraform apply upgrade.tfplan
```

Do not use `terraform init -upgrade` to request a Kubernetes upgrade; it changes Terraform provider/module dependency selection, not `kubernetes_version`.

### 3. Increase workers from three to five

This change increases the existing single worker pool in each cluster. Keep `control_plane_count = 3`, the Kubernetes release, ClusterClass and VM/storage settings unchanged. In the `module "vks_cluster"` block of DEV `main.tf`, change the existing assignment:

```hcl
worker_count = 5
```

The module maps this value to `spec.topology.workers.machineDeployments[0].replicas`. Edit the root's literal assignment; `worker_count` is a module input and is not declared as a root CLI variable, so `terraform -var='worker_count=5'` is not the interface for these roots.

| Capacity | Before, per cluster | After, per cluster | Increase across DEV and QA |
| --- | --- | --- | --- |
| Control-plane nodes | 3 | 3 | 0 |
| Worker nodes | 3 | 5 | 4 workers |
| Total nodes | 6 | 8 | 4 nodes; 16 total |
| Worker containerd volumes | 90 GiB | 150 GiB | 120 GiB; 300 GiB total |

These storage figures cover only the configured `30Gi` worker volumes. Add OS disks, application volumes and any temporary rollout capacity when sizing quotas. Four additional workers also require sufficient compute and network address capacity.

Plan DEV first:

```bash
cd terraform-create-vks-cluster/dev-cluster-01
terraform validate
terraform plan -out=scale-workers-5.tfplan
terraform show -no-color scale-workers-5.tfplan
```

The intended infrastructure change is an in-place Cluster update from three to five worker replicas, with no control-plane or release change. The local YAML may also be updated or replaced, including when its dated path changes. Do not accept a Cluster replacement. After reviewing the plan:

```bash
terraform apply scale-workers-5.tfplan
```

Wait for DEV to have five ready workers using the completion checks below. Then change `worker_count = 5` in QA `main.tf`, return to the repository root (`terraform-vks/`), and repeat:

```bash
cd terraform-create-vks-cluster/qa-cluster-02
terraform validate
terraform plan -out=scale-workers-5.tfplan
terraform show -no-color scale-workers-5.tfplan
# Run only after reviewing the QA plan.
terraform apply scale-workers-5.tfplan
```

Terraform continues to manage one Cluster resource per root; it will not show two new worker-VM resources in its plan. VKS reconciles the replica change into new Machines. Keep Terraform as the lifecycle owner rather than using a parallel `kubectl scale` or manifest-edit workflow. Broadcom's [horizontal scaling documentation](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-0/managing-vsphere-kuberenetes-service-clusters-and-workloads/operating-tkg-service-clusters/manually-scale-a-cluster-using-kubectl.html) explains the underlying node-count operation.

### 4. Verify completion

After each apply, inspect the affected Cluster and its Machines. These read-only commands cover both targets:

```bash
kubectl config use-context supervisor
kubectl -n dev-namespace get clusters.cluster.x-k8s.io dev-cluster-01 -o yaml
kubectl -n dev-namespace get machines.cluster.x-k8s.io -l cluster.x-k8s.io/cluster-name=dev-cluster-01
kubectl -n dev-namespace get events --sort-by=.metadata.creationTimestamp

kubectl -n qa-namespace get clusters.cluster.x-k8s.io qa-cluster-02 -o yaml
kubectl -n qa-namespace get machines.cluster.x-k8s.io -l cluster.x-k8s.io/cluster-name=qa-cluster-02
kubectl -n qa-namespace get events --sort-by=.metadata.creationTimestamp
```

Authenticate to each workload cluster using the established lab access procedure. Run the following for each cluster, replacing `WORKLOAD_CONTEXT` with its actual authenticated context name; do not use `supervisor` for these workload checks:

```bash
kubectl config use-context WORKLOAD_CONTEXT
kubectl get nodes -o wide
kubectl get pods -A
```

Completion requires all of the following:

- The latest Cluster specification has reconciled. Check observed generation where reported, current conditions and Machine progress; an old `Available=True` condition alone is insufficient.
- For scaling: exactly three ready control-plane nodes and five ready workers per changed cluster, with no pending or failed Machines. Desired replicas of five alone do not prove capacity was added.
- For upgrading: all control-plane and worker nodes report the target Kubernetes version, all are ready, and the rollout has finished. Supervisor-normalized release identifiers may differ from the requested VKr name; verify the resolved release and node versions agree with the selected target.
- Workload API access, system components, application health checks, persistent storage and ingress work after the change.

Finally, run a fresh `terraform plan` for the changed root and review residual differences. Investigate unexpected Cluster drift. A dated local YAML path can produce a file-only difference on a subsequent day; do not confuse that with an incomplete Kubernetes rollout.

### 5. Failed or interrupted changes

If apply times out or returns an inconsistent-result error, inspect the Cluster, Machines, events and Terraform state before issuing another mutation. The API may have accepted the request and controllers may still be working. Do not force conflicts, delete Machines, destroy/recreate the Cluster or reapply an old saved plan as an automatic recovery step.

Changing five workers back to three is a separate scale-down operation involving workload placement and possible disruption; assess PodDisruptionBudgets and capacity before planning it. Reverting `kubernetes_version` is not a guaranteed rollback and can request an unsupported downgrade. For a failed release rollout, use the installed VKS recovery procedure and a supported forward fix or application restore plan.

### 6. Upgrade Terraform providers separately

For a deliberate dependency upgrade, preserve current lock files and state, review the candidate providers' release notes, and run the following for DEV first:

```bash
cd terraform-create-vks-cluster/dev-cluster-01
terraform init -upgrade
terraform validate
terraform plan
```

Review the lock-file changes and any resulting resource differences before proceeding. After DEV verification, return to the repository root (`terraform-vks/`), run `cd terraform-create-vks-cluster/qa-cluster-02`, and repeat the same plain Terraform commands. `init -upgrade` can update both Kubernetes and Local providers within their constraints. It neither changes the desired Kubernetes release nor proves that a cluster upgrade has completed.

## Adopt an existing cluster

Only use import when the named Cluster already exists and is not managed in the selected state. From the repository root (`terraform-vks/`), run the applicable import below. The second `cd` moves from DEV to QA if running both imports; for QA alone, use `cd terraform-create-vks-cluster/qa-cluster-02` instead:

```bash
# Existing DEV Cluster
cd terraform-create-vks-cluster/dev-cluster-01
terraform import module.vks_cluster.kubernetes_manifest.cluster 'apiVersion=cluster.x-k8s.io/v1beta2,kind=Cluster,namespace=dev-namespace,name=dev-cluster-01'

# Existing QA Cluster
cd ../qa-cluster-02
terraform import module.vks_cluster.kubernetes_manifest.cluster 'apiVersion=cluster.x-k8s.io/v1beta2,kind=Cluster,namespace=qa-namespace,name=qa-cluster-02'
```

Generate and review a fresh plan for each imported Cluster before applying. Resolve field ownership conflicts deliberately; the module uses `force_conflicts = false`.

## Delete a cluster

From the repository root (`terraform-vks/`), run only the removal you intend. The second `cd` moves from DEV to QA if removing both; for QA alone, use `cd terraform-create-vks-cluster/qa-cluster-02` instead:

```bash
# Delete DEV
cd terraform-create-vks-cluster/dev-cluster-01
terraform destroy

# Delete QA
cd ../qa-cluster-02
terraform destroy
```

Each command displays its own plan and requires `yes` to proceed. Review the namespace and Cluster name before confirming. Each root manages its Cluster and generated YAML file; the existing namespace and CA Secret remain.

After deletion, use the matching kubectl commands in [Verify both clusters](#4-verify-both-clusters). The Cluster should return `NotFound`, and its machine query should return no resources. Run `terraform state list` from the corresponding cluster directory as well. If deletion times out, inspect remaining objects and deletion conditions before further action. Preserve state until cleanup is resolved.

## API behavior and troubleshooting

The Kubernetes provider uses the Supervisor endpoint and authentication from kubeconfig. This workflow does not call the vCenter management REST API or use shell provisioners.

| Resource | Provider-managed operations | Result |
| --- | --- | --- |
| `module.vks_cluster.kubernetes_manifest.cluster` | Discovery/schema reads; GET/PATCH/DELETE under `/apis/cluster.x-k8s.io/v1beta2/namespaces/{namespace}/clusters/{name}` | Reads, applies or deletes the Cluster; provider handles transport/status checks, while VKS reconciliation requires separate verification |
| `local_file.cluster_manifest` | Local file creation/update/deletion | Writes the desired YAML; no API call or readiness check |

| Symptom | Check |
| --- | --- |
| Authentication or connection failure | Refresh Supervisor credentials and verify kubeconfig context, endpoint and TLS settings. |
| Missing Cluster kind during plan | Verify the selected Supervisor exposes the required CRD/version and allows discovery. |
| Admission rejection | Check release, ClusterClass, namespace bindings, quota, networks and referenced Secrets. |
| Timeout or inconsistent result after apply | Inspect the live Cluster and Terraform state before another mutation; the Cluster may already exist. |
| Unexpected replacement | Inspect state, taint and configuration differences before applying. |

The module includes the observed Supervisor default `podSecurityStandard.deactivated = false` and marks topology variables, version, labels and annotations as computed. These accommodate admission defaults and release normalization. Earlier configurations produced `Provider produced inconsistent result after apply` despite creating the Cluster. Use a fresh plan with the current module and inspect state before recovery.

## Output

The following files record Terraform deployment activity and the resulting DEV and QA cluster inventory.

| Cluster | Output | Description |
| --- | --- | --- |
| `dev-cluster-01` | [Terraform deployment output](terraform-create-vks-cluster/dev-cluster-01/terraform-out.txt) | Saved terminal transcript containing initialization, plans, applies, deletion/recreation activity, Terraform output values, and cluster checks. The final check records `Available=True`, three available control-plane nodes, and three available workers. |
| `dev-cluster-01` | [Cluster documentation output](output/document-vks-dev-cluster-01-2026-10-22-13-21-53.txt) | Read-only cluster inventory captured on **2026-10-22 at 13:21:53 GMT**. Includes networking, node configuration and conditions, workloads, storage, CNI/CSI components, events, resource usage, and container images. Records six Ready nodes. |
| `qa-cluster-02` | [Terraform deployment output](terraform-create-vks-cluster/qa-cluster-02/terraform-out.txt) | Saved terminal transcript containing initialization, plans, applies, deletion/recreation activity, Terraform output values, and cluster checks. The final check records `Available=True`, three available control-plane nodes, and three available workers. |
| `qa-cluster-02` | [Cluster documentation output](output/document-vks-qa-cluster-02-2026-10-22-13-22-26.txt) | Read-only cluster inventory captured on **2026-10-22 at 13:22:26 GMT**. Includes networking, node configuration and conditions, workloads, storage, CNI/CSI components, events, resource usage, and container images. Records six Ready nodes. |

The Terraform files are complete command transcripts, not captures of `terraform output` alone. They retain intermediate provisioning states and typed-command errors; follow the procedures in this README when executing commands. The QA Terraform directory and cluster are both named `qa-cluster-02`.

The cluster documentation files were generated by separate read-only collectors, not Terraform. Both report completed collection and zero writes attempted. Their embedded absolute paths refer to the original lab checkout; the links above open the copies in this repository.

These outputs describe historical observations. Use the [cluster verification procedure](#4-verify-both-clusters) to establish current readiness. See [Generated files and outputs](#generated-files-and-outputs) for the desired YAML manifests and Terraform output values.

## References

- [HashiCorp Kubernetes provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs) — provider configuration and authentication.
- [Kubernetes manifest resource](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) — custom resources, computed fields, field management and import.
- [HashiCorp Kubernetes provider tutorial](https://developer.hashicorp.com/terraform/tutorials/kubernetes/kubernetes-provider) — why custom-resource planning requires an existing API schema.
- [Local file resource](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) — local artifact lifecycle and permissions.
- [Terraform dependency lock file](https://developer.hashicorp.com/terraform/language/files/dependency-lock) and [terraform init](https://developer.hashicorp.com/terraform/cli/commands/init) — reproducible provider selection and deliberate dependency upgrades.
