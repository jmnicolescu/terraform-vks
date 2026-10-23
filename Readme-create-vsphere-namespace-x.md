<!--
author: "Julius M. Nicolescu"
date: "October 2026"
description: "Technical guide to creating and managing DEV and QA vSphere namespaces through the vCenter REST API with Terraform, including namespace descriptions, per-storage-policy limits, VM Service bindings, reusable modules, and independent environment state."
keywords: ["VCF", "vSphere", "Supervisor", "Terraform", "Namespaces", "REST API", "Storage policies"]
lang: en
-->

# Create vSphere namespaces with Terraform — REST alternative

This project creates `dev-namespace` and `qa-namespace` through the vCenter REST API, including descriptions, per-policy storage limits, and VM Service bindings. The default [native implementation](Readme-create-vsphere-namespace.md) uses native `vsphere_namespace` for lifecycle plus read-only Supervisor discovery. Keep their states separate and never manage the same namespace with both.

## GitHub repository

**Repository:** [github.com/jmnicolescu/terraform-vks](https://github.com/jmnicolescu/terraform-vks)

Access the Terraform projects, deployment guides, and captured output files in this repository.

## Contents

- [Requirements: Supervisor connection](#requirements-supervisor-connection)
- [GitHub repository](#github-repository)
- [Tested environment and versions](#tested-environment-and-versions)
- [Prerequisites](#prerequisites)
- [Directory structure and configuration](#directory-structure-and-configuration)
- [How the shared module calls work](#how-the-shared-module-calls-work)
- [Create DEV vSphere namespace](#create-dev-vsphere-namespace)
- [Namespace changes and upgrades](#namespace-changes-and-upgrades)
- [Create QA vSphere namespace](#create-qa-vsphere-namespace)
- [How to delete the namespace](#how-to-delete-the-namespace)
- [Outputs and completion](#outputs-and-completion)
- [API operations and troubleshooting](#api-operations-and-troubleshooting)
- [Output](#output)
- [References](#references)

## Tested environment and versions

The target environment is the VCF 9.1.1 lab. The VCF build identifier comes from the repository documentation; the Terraform CLI and provider versions below were used for offline validation on 2026-10-22. The supplied transcripts now record namespace applies and deletion/recreation activity; their final read-back remains `CONFIGURING`. The separate inventory report records both namespaces as `RUNNING` at capture time. See [Output](#output) for the evidence and its limits.

| Component | Version or contract |
| --- | --- |
| VMware Cloud Foundation target | `9.1.1.0-545627-2026-09` |
| Terraform CLI used for offline checks | `1.16.6` (`darwin_arm64`) |
| vSphere provider (`vmware/vsphere`) | `2.17.1`; configured constraint `~> 2.16` |
| REST provider (`Mastercard/restapi`) | `2.0.1`; configured constraint `~> 2.0` |
| Session provider (`magodo/restful`) | `0.25.2`; configured constraint `~> 0.25.2` |
| Minimum Terraform version for the roots | `1.10.0`, required for ephemeral sessions and credential inputs |
| VCF API specification | `9.1.1.0`, bundle `vcf-api-specs-9.1.1.0-25714914` |
| Namespace API used by this module | vCenter `/api/vcenter/namespaces/instances`, single-cluster CreateSpec |

Provider versions and package checksums are recorded separately in the [DEV lock file](terraform-create-vsphere-namespace-x/dev-namespace/.terraform.lock.hcl) and [QA lock file](terraform-create-vsphere-namespace-x/qa-namespace/.terraform.lock.hcl). The namespace payload follows the original lab vCenter OpenAPI specification (not included in this export) and `01-create-namespace.sh` from the original lab checkout (not included in this export). A version constraint permits compatible provider selections; the lock file records the version actually selected.

DEV requests `dev-namespace` with description `Dev Namespace`; QA requests `qa-namespace` with description `QA Namespace`. Both assign a limit of **512000 MiB (500 GiB) per storage policy**. The goal is to describe each namespace in Terraform, review it with `terraform plan`, submit it with `terraform apply`, and remove the managed namespace with `terraform destroy`. The existing Supervisor supplies the infrastructure on which namespace configuration is reconciled.

We use a reusable module to keep inventory resolution, payload construction and validation in one place. Each root contains its deployment settings, configured providers and independent state. Another namespace can call the module with different inputs without copying the lifecycle logic. The module is a local collection of Terraform files; it does not deploy another service.

Internally, the root configures inventory, namespace and session providers against the same vCenter. Terraform automatically opens an ephemeral REST session, supplies it to the namespace provider, and closes it after successful operations. The module uses vSphere data sources to resolve names into inventory IDs, builds `local.create_spec`, and manages a single `restapi_object.namespace`. Terraform tracks that namespace; vCenter and Supervisor reconcile the accepted configuration. The module reads back state but does not wait for `RUNNING`.

The provider decision follows the fields this workflow must manage:

| Provider or approach | Decision and reason |
| --- | --- |
| `vmware/vsphere` | Used for datacenter, compute-cluster, storage-policy and content-library lookups. This keeps readable names in the root configuration while supplying the IDs required by the namespace API. |
| Native `vsphere_namespace` resource | Not used for lifecycle management: the reviewed resource schema exposes namespace identity, Supervisor, VM Service bindings and storage-policy IDs, but does not expose the required namespace description or per-policy limit. Using it alone would leave required settings unmanaged. |
| `Mastercard/restapi` | Used for namespace creation, reads, updates and deletion. It can submit the vCenter CreateSpec and a separate UpdateSpec containing descriptions and storage limits. The tradeoff is that endpoint contracts, payloads and readiness interpretation must be maintained by this module and its operator. |
| `hashicorp/kubernetes` / `gavinbunney/kubectl` | Not configured. The managed object is a vCenter vSphere namespace with storage-policy limits and VM Service bindings. The VKS template uses a Kubernetes Cluster custom resource, which is a different API contract. Creating an ordinary Kubernetes Namespace does not express this module's vCenter configuration. |
| `hashicorp/local` | Not configured because the current roots expose the desired JSON payload as an output and do not manage a generated file. The VKS workflow uses this provider for its YAML artifact. |
| `magodo/restful` | Manages only the temporary login session through an ephemeral resource. It opens the session with POST, supplies the token to `restapi`, and revokes it with DELETE when Terraform closes the session. The token is excluded from state and saved plans. |
| `hashicorp/http` data-source login | Not selected: a login data source would retain its response in state and provides no matching automatic logout lifecycle. |
| Shell provisioners | Not used. Authentication and namespace operations are Terraform provider operations; no curl, sourced Bash file or token-copy step is required. |

The native-resource limitation is documented in the [vSphere namespace reference](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/resources/namespace); the chosen lifecycle controls are documented in the [REST object reference](https://registry.terraform.io/providers/Mastercard/restapi/latest/docs/resources/object). Review these contracts before a provider upgrade rather than assuming every future release behaves identically.

The literal namespace settings were copied from `00-vcf9-env.sh` (original lab configuration, not included in this export). Terraform does not source that file. Keep the module inputs synchronized manually. Both roots now contain a private `terraform.tfvars` populated once from the existing literal lab connection settings. Terraform reads those files directly. Later changes to 00 are not automatically imported; update the selected Terraform settings when credentials or endpoints change.

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

- Terraform >= 1.10 and the providers declared in the root `main.tf` and module `versions.tf`. `terraform init` installs the locked versions.
- Reachable vCenter with the existing datacenter and Supervisor-enabled cluster. Planning performs inventory lookups and state refreshes, so connectivity is required for plan as well as apply.
- Existing storage policies, VM classes and content libraries, with sufficient storage and compute capacity for the intended workloads. Configured names are source settings, not proof of live availability.
- A vCenter account with inventory visibility and `Namespaces.Configure`. Exact role composition has not been tested live. Terraform obtains the REST session automatically using the same configured account and password as the vSphere inventory provider.
- TLS settings matching the environment. The current roots default to the lab's `insecure_tls = true`. With verification enabled, configure trusted certificates for all three providers.
- Existing Supervisor-wide Kubernetes Service library access if VKS will consume these namespaces. This module assigns namespace VM Service libraries but does not update shared Supervisor image settings.

Shared library settings are intentionally outside the two independent namespace states: both namespaces can use the same Supervisor, and two owners of that shared configuration could overwrite each other's changes. This module also does not create the Supervisor, grant user access, configure namespace networking overrides or deploy VKS clusters. Do not run the original lab namespace creation or deletion scripts (`01-create-namespace.sh` or script 05) against a namespace already managed by Terraform. The local `utilities/01-create-supervisor-context.sh` utility only configures access and is separate from those lifecycle scripts.

## Directory structure and configuration

This guide is in the repository root, alongside `terraform-create-vsphere-namespace-x/`.

```text
terraform-create-vsphere-namespace-x/
├── .gitignore
├── dev-namespace/
│   ├── main.tf
│   ├── variables.tf
│   ├── auth.tf
│   ├── terraform.tfvars
│   └── .terraform.lock.hcl
├── qa-namespace/
│   ├── main.tf
│   ├── variables.tf
│   ├── auth.tf
│   ├── terraform.tfvars
│   └── .terraform.lock.hcl
└── modules/
    └── vsphere-namespace/
        ├── main.tf
        ├── variables.tf
        ├── versions.tf
        └── outputs.tf
```

Run Terraform from the root for the selected namespace. Each root owns its own `.terraform/` metadata, state and plans. The resource address is the same in both states; the directory determines the target. Never copy state or saved plans between DEV and QA. Generated metadata and private backups are omitted from the tree. There is no `cleanup.sh` in this workflow.

### Select the namespace

| Setting | DEV | QA |
| --- | --- | --- |
| Terraform directory / namespace | `dev-namespace` | `qa-namespace` |
| Description | `Dev Namespace` | `QA Namespace` |
| Datacenter | `platformlab-dc01` | `platformlab-dc01` |
| Supervisor-enabled cluster | `platformlab-cl01` | `platformlab-cl01` |
| Storage policy | `vSAN Default Storage Policy` | `vSAN Default Storage Policy` |
| Limit per policy | `512000` MiB | `512000` MiB |
| VM Service content library | `vkr-content-library` | `vkr-content-library` |
| VM classes | `best-effort-small`, `best-effort-medium`, `best-effort-large`, `best-effort-xlarge` | Same four classes |

Both roots call `../modules/vsphere-namespace`. A shared module edit affects future plans for both roots; applying DEV changes only DEV's state and managed namespace.

| File | Purpose |
| --- | --- |
| [DEV main.tf](terraform-create-vsphere-namespace-x/dev-namespace/main.tf) / [QA main.tf](terraform-create-vsphere-namespace-x/qa-namespace/main.tf) | Provider connections, literal inputs, module call and root outputs |
| [DEV variables.tf](terraform-create-vsphere-namespace-x/dev-namespace/variables.tf) / [QA variables.tf](terraform-create-vsphere-namespace-x/qa-namespace/variables.tf) | Connection inputs and sensitive, ephemeral credential variables |
| [DEV lock file](terraform-create-vsphere-namespace-x/dev-namespace/.terraform.lock.hcl) / [QA lock file](terraform-create-vsphere-namespace-x/qa-namespace/.terraform.lock.hcl) | Selected provider versions and checksums |
| [DEV auth.tf](terraform-create-vsphere-namespace-x/dev-namespace/auth.tf) / [QA auth.tf](terraform-create-vsphere-namespace-x/qa-namespace/auth.tf) | Automatic ephemeral session login and logout |
| `dev-namespace/terraform.tfvars` / `qa-namespace/terraform.tfvars` | Private literal connection values; already populated, excluded from version control |
| [Module main.tf](terraform-create-vsphere-namespace-x/modules/vsphere-namespace/main.tf) | Inventory lookups, CreateSpec/UpdateSpec and managed resource |
| [Module variables.tf](terraform-create-vsphere-namespace-x/modules/vsphere-namespace/variables.tf) | Reusable inputs and validation |
| [Module versions.tf](terraform-create-vsphere-namespace-x/modules/vsphere-namespace/versions.tf) | Terraform and provider requirements |
| [Module outputs.tf](terraform-create-vsphere-namespace-x/modules/vsphere-namespace/outputs.tf) | Identity, cluster ID, desired payload and observed status |

| Module input | Required/default | Meaning |
| --- | --- | --- |
| `namespace_name` | Required | Lowercase DNS label, 1–63 characters; namespace identity |
| `description` | Required | vCenter namespace description |
| `datacenter_name` | Required | Existing datacenter scoping the cluster lookup |
| `cluster_name` | Required | Existing Supervisor-enabled cluster |
| `storage_policy_names` | Required | Nonempty list without duplicates; resolved to policy IDs |
| `storage_limit_mib` | `512000` | Nonnegative integer limit for each policy, in MiB |
| `content_library_names` | `[]` | Existing namespace VM Service libraries |
| `vm_classes` | `[]` | Existing VM class names to assign |

Root connection inputs are `vcenter`, `insecure_tls`, `vcenter_user` and `vcenter_password`. The private `terraform.tfvars` files already contain the existing lab values, so no credential-entry step is required for this checkout. Credentials are marked both sensitive and ephemeral; Terraform does not persist these inputs in state or saved plans. Keep the local files private (`0600`) and excluded from commits. There is no session-ID input. Avoid provider debug logs because HTTP logging can include authentication headers.

### Namespace storage limit

Each namespace requests 512000 MiB, equivalent to 500 GiB, for `vSAN Default Storage Policy`. The limit is copied into each entry in `storage_specs`; adding another policy gives that policy the same configured limit. It is not a single aggregate cap across all policies, a storage reservation or a preallocated disk. With the one configured policy, DEV and QA each have a 500 GiB limit; this does not establish 1000 GiB of available physical capacity.

Set `storage_limit_mib` in the selected root to change the requested limit. This is the namespace counterpart of the VKS template's worker-volume section: namespace quota limits consumption, while the VKS module requests individual worker volumes. Increasing quota does not resize existing VM disks.

## How the shared module calls work

Each root chooses **where to connect** and **what namespace to request**. The shared module defines **how names become API IDs and how the namespace request is managed**. Edit root inputs for deployment-specific settings; edit the shared module for behavior intended for every caller.

### Connect the module to vCenter

The root's inventory and namespace providers use the same vCenter:

```hcl
provider "vsphere" {
  vsphere_server       = var.vcenter
  user                 = var.vcenter_user
  password             = var.vcenter_password
  allow_unverified_ssl = var.insecure_tls
}

provider "restapi" {
  uri                  = "https://${var.vcenter}"
  insecure             = var.insecure_tls
  timeout              = 120
  write_returns_object = false
  debug                = false
  headers = {
    "vmware-api-session-id" = ephemeral.restful_resource.vcenter_session.sensitive_output
    "Content-Type"          = "application/json"
  }
}
```

[auth.tf](terraform-create-vsphere-namespace-x/dev-namespace/auth.tf) creates and closes the temporary session automatically:

```hcl
provider "restful" {
  base_url = "https://${var.vcenter}"
  client = {
    tls_insecure_skip_verify = var.insecure_tls
  }
}

ephemeral "restful_resource" "vcenter_session" {
  path                 = "/api/session"
  method               = "POST"
  use_sensitive_output = true
  open_header = {
    Authorization = "Basic ${base64encode("${var.vcenter_user}:${var.vcenter_password}")}"
  }
  close_path   = "/api/session"
  close_method = "DELETE"
  close_header = {
    "vmware-api-session-id" = "$(body)"
  }
}
```

`required_providers` selects provider packages and versions; the provider blocks supply connections. Default `vsphere` and `restapi` configurations are inherited by the namespace module without an explicit provider map. The VKS template passes an aliased Kubernetes connection; this workflow targets vCenter directly. The `restful` provider is used only in the root for authentication.

Terraform opens the ephemeral resource before configuring `restapi`. The response from `POST /api/session` is the token, exposed as sensitive ephemeral output. Terraform passes it directly into the namespace provider's header. The `$(body)` expression is the session provider's response substitution for logout; it is not shell code. When the dependent provider has finished, Terraform closes the session with `DELETE /api/session`.

Each plan/apply phase obtains its own session, including applying a saved plan. The token is not saved with the plan, and the current credential variables are supplied again from `terraform.tfvars`. No namespace payload or module input contains authentication data.

| Setting | Reason |
| --- | --- |
| Sensitive, ephemeral credential variables | Supply provider authentication without persisting those inputs in plans or state |
| `use_sensitive_output = true` | Hides the session response in normal Terraform output |
| `close_method = "DELETE"` | Automatically revokes the session on normal completion |
| `write_returns_object = false` | Namespace writes return HTTP 204 with no object body; the resource reads state with GET |
| `object_id = var.namespace_name` | Uses the known namespace identity without expecting it in the create response |
| `timeout = 120` | Bounds namespace REST requests; the session provider does not expose an equivalent request-timeout setting |
| No retry configuration | Avoids automatically repeating an uncertain namespace mutation |

Normal session opening and closing were verified against a mock API. Failed apply testing found that Terraform can skip the ephemeral close operation after a resource error; an interrupted run can also leave a session until vCenter expires it. This is a cleanup limitation, not a reason to repeat a namespace mutation. Sessions are not renewed during a long-running phase. See [Output](#output).

### Supply the desired namespace settings

The DEV module call is:

```hcl
module "vsphere_namespace" {
  source = "../modules/vsphere-namespace"

  namespace_name        = "dev-namespace"
  description           = "Dev Namespace"
  datacenter_name       = "platformlab-dc01"
  cluster_name          = "platformlab-cl01"
  storage_policy_names  = ["vSAN Default Storage Policy"]
  storage_limit_mib     = 512000
  content_library_names = ["vkr-content-library"]
  vm_classes            = ["best-effort-small", "best-effort-medium", "best-effort-large", "best-effort-xlarge"]
}
```

`module "vsphere_namespace"` names this module instance in Terraform addresses. The actual namespace name comes from `namespace_name`. The relative `source` selects the shared directory from either root, and Terraform loads its `.tf` files as one module. Each assignment supplies the corresponding variable in `variables.tf`; for example, `storage_limit_mib = 512000` becomes `var.storage_limit_mib` and sets every storage-policy entry's `limit`.

- **Identity and placement:** namespace name, datacenter and cluster select the object and its existing Supervisor-enabled infrastructure.
- **Description:** the supplied text becomes the namespace description in vCenter.
- **Storage:** policy names resolve to IDs and each gets the requested MiB limit.
- **VM Service bindings:** existing library names resolve to IDs; VM classes are supplied by name. Their availability and compatibility require live platform validation.

### From inputs to a configured namespace

Terraform reads the datacenter, scoped compute cluster, policies and libraries through vSphere data sources. The module builds `local.settings` for mutable properties, then adds `cluster` and `namespace` to form `local.create_spec`. The resource at `module.vsphere_namespace.restapi_object.namespace` uses POST to create, GET to read, PATCH to update and DELETE to remove the namespace.

Updates use `jsonencode(local.settings)`, so create-only identity fields are not sent in the UpdateSpec. The resource forces replacement if namespace identity or the resolved cluster changes. Its read-back supplies `config_status`; `RUNNING` means namespace configuration is complete, while `CONFIGURING` means reconciliation continues.

For example, changing `storage_limit_mib` to `1024000` requests 1000 GiB per policy without editing the module. Review a fresh plan before applying. Terraform submits the changed configuration; vCenter determines whether the requested limit is admissible and applies it asynchronously. Workload readiness remains a separate check.

## Create DEV vSphere namespace

The connection files are already populated. From the repository root (`terraform-vks/`), run:

```bash
cd terraform-create-vsphere-namespace-x/dev-namespace
terraform init
terraform validate
terraform plan
terraform apply
```

`terraform apply` displays a fresh plan and asks for confirmation. Terraform handles login, passes the session to the namespace provider, and logs out on normal completion. Review the requested namespace and storage settings before confirming. No curl command, sourced configuration, environment export or manual session ID is needed.

For a saved-plan workflow, use:

```bash
terraform plan -out=namespace.tfplan
terraform apply namespace.tfplan
```

Applying a saved plan obtains a new ephemeral session and does not ask for another confirmation. Keep `terraform.tfvars` available so Terraform can read the ephemeral credential inputs at apply time.

If DEV already exists outside this state, import it before planning:

```bash
terraform import module.vsphere_namespace.restapi_object.namespace \
  /api/vcenter/namespaces/instances/dev-namespace
terraform plan
```

Import authenticates automatically as well. Review differences before applying; the module manages complete storage-policy and VM Service binding lists. After an uncertain create, inspect the namespace in vSphere Client and Terraform state before retrying. Do not manage the same namespace through both Terraform and scripts 01/05.

For later connection changes, edit the literal values in the selected root's private `terraform.tfvars`. Do not add a session token; Terraform supplies it at runtime.

## Namespace changes and upgrades

The same module and state manage creation and subsequent changes. Edit the selected root's `module "vsphere_namespace"` block:

| Operation | Input | Expected behavior |
| --- | --- | --- |
| Change description | `description` | PATCH namespace description |
| Change storage limit | `storage_limit_mib` | PATCH each policy's limit; check current usage and platform constraints |
| Change assigned policies | `storage_policy_names` | Resolve IDs and submit the desired policy list |
| Change VM Service bindings | `vm_classes`, `content_library_names` | Submit the desired bindings; check existing workloads and available images |
| Rename or move namespace | `namespace_name`, resolved cluster | Replacement, with deletion consequences; not an in-place rename or migration |
| Upgrade Terraform providers | Version constraints / lock file | Separate tooling change; revalidate contracts and inspect both root plans |

For example, request a 1000 GiB limit per policy:

```hcl
storage_limit_mib = 1024000
```

From the selected namespace root:

```bash
terraform plan -out=namespace.tfplan
terraform apply namespace.tfplan
```

A description or quota change should show an **in-place update** of `module.vsphere_namespace.restapi_object.namespace`. Investigate any proposed replacement before applying. Keep state; do not remove it to prepare for an update. Verify the resulting description, limits and `RUNNING` status after apply.

This is the counterpart of the VKS template's cluster-change chapter. Kubernetes versions, node counts and worker disk sizes belong to the VKS module; changing namespace quota does not upgrade a workload cluster. Supervisor upgrades are outside this module. Provider upgrades change the tooling, not the namespace's Kubernetes version. The mock fixture covered description and limit updates; live updates and provider upgrades remain unverified.

## Create QA vSphere namespace

[qa-namespace/main.tf](terraform-create-vsphere-namespace-x/qa-namespace/main.tf) calls the same module with QA identity and its own state, lock file and plans. Settings are literal assignments copied from 00; Terraform does not load the Bash configuration at runtime.

| QA setting | Value |
| --- | --- |
| Namespace / description | `qa-namespace` / `QA Namespace` |
| Datacenter / cluster | `platformlab-dc01` / `platformlab-cl01` |
| Storage policy / limit | `vSAN Default Storage Policy` / `512000` MiB |
| VM Service library | `vkr-content-library` |
| VM classes | `best-effort-small`, `best-effort-medium`, `best-effort-large`, `best-effort-xlarge` |

QA already has its own private connection settings. From the repository root (`terraform-vks/`):

```bash
cd terraform-create-vsphere-namespace-x/qa-namespace
terraform init
terraform validate
terraform plan -out=namespace.tfplan
terraform apply namespace.tfplan
```

If QA already exists, import it before planning, from `qa-namespace`:

```bash
terraform import module.vsphere_namespace.restapi_object.namespace \
  /api/vcenter/namespaces/instances/qa-namespace
terraform plan
```

Review differences before apply. Run later plans, updates and destruction from the QA root. Never copy DEV state or saved plans into QA. Initialization and validation alone do not deploy QA; the saved QA transcript separately records an apply, as described under [Output](#output). Authentication and normal session cleanup are automatic, as in DEV.

## How to delete the namespace

Deletion removes the selected namespace and its workloads. First remove any Terraform-managed VKS clusters through their own VKS state and verify their cleanup; deleting their enclosing namespace first can leave those other states out of sync.

From the repository root (`terraform-vks/`), choose one root:

| Namespace to delete | Directory command |
| --- | --- |
| DEV | `cd terraform-create-vsphere-namespace-x/dev-namespace` |
| QA | `cd terraform-create-vsphere-namespace-x/qa-namespace` |

Then run:

```bash
terraform plan -destroy
terraform destroy
```

Review the identity of `module.vsphere_namespace.restapi_object.namespace`. For an existing managed namespace, the expected resource plan is **0 to add, 0 to change, 1 to destroy**. Inventory data sources are reads, not managed infrastructure to delete. `terraform destroy` displays a plan and asks for confirmation. The other root's state is independent.

The API accepts deletion asynchronously; a successful destroy and empty managed-resource state do not establish that vCenter has finished cleanup. Check the state:

```bash
terraform state list
```

Then verify in vSphere Client that the selected namespace is absent and its removal tasks completed. If deletion remains pending or a request failed, inspect current state before another mutation. Existing datacenter, cluster, policies, libraries and Supervisor-wide library settings remain because they are not owned by this resource. Terraform handles authentication for destroy automatically.

After confirmed deletion, recreate with a fresh plan if intended:

```bash
terraform plan -out=namespace.tfplan
terraform apply namespace.tfplan
```

There is no generated-file cleanup script. Retain state records and lock files; never delete state to remove a namespace.

## Outputs and completion

| Output | Module | Root | Meaning |
| --- | --- | --- | --- |
| `namespace_name` | Yes | Yes | Managed namespace identity |
| `cluster_id` | Yes | No | Resolved compute-cluster ID |
| `create_spec` | Yes | Yes | Desired create payload with resolved inventory IDs |
| `config_status` | Yes | Yes | Last observed API status, or `UNKNOWN` if unavailable |

From the selected root:

```bash
terraform output namespace_name
terraform output config_status
terraform output -json create_spec
```

Outputs are state snapshots. A successful apply means the provider completed its operation; the module does not poll for readiness. To read current state with automatic authentication:

```bash
terraform plan -refresh-only
terraform apply -refresh-only
terraform output config_status
```

A refresh-only operation reads the namespace and updates local state after confirmation; it does not change namespace configuration. Confirm `RUNNING` and the requested settings in vSphere Client. `CONFIGURING` is pending; inspect namespace messages and tasks if the status is `ERROR`. Namespace readiness does not prove VKS release availability, worker readiness or application health.

### Export the namespace payload

This section corresponds to the VKS template's automatic YAML generation. The namespace implementation currently exposes `create_spec` as JSON and has no `local_file` resource, `manifest_file` output or automatic dated output directory. The decision avoids adding a file-management provider when the managed API consumes JSON and the desired payload is already available as an output.

If a review artifact is needed, explicitly export it from the selected root after state contains the output:

```bash
terraform output -json create_spec > create-namespace.json
chmod 600 create-namespace.json
```

The file records desired settings and resolved IDs, not operational status or credentials. It is a vCenter API body, not a Kubernetes manifest for `kubectl apply`. The `chmod` command restricts the exported file to its owner. Terraform does not track this manual export, so destroy will not remove it; retain it privately and refresh it deliberately when inputs change. Do not submit it independently against a namespace whose lifecycle is already managed by Terraform.

## API operations and troubleshooting

REST base URL: `https://<vCenter>`. Namespace requests use the `vmware-api-session-id` header. Namespace request timeout is 120 seconds; the session provider uses its own transport and does not expose a request-timeout option. No automatic retry configuration is enabled. Generic REST provider success handling accepts successful HTTP statuses; the table records the expected vCenter contract.

| Operation | Method and endpoint | Expected result |
| --- | --- | --- |
| Ephemeral session open | `POST /api/session` with Basic authentication | 201; session token |
| Create | `POST /api/vcenter/namespaces/instances` | 204; creation accepted |
| Read | `GET /api/vcenter/namespaces/instances/{namespace}` | 200; Info including `config_status`; 404 if absent |
| Update | `PATCH /api/vcenter/namespaces/instances/{namespace}` | 204; update accepted |
| Delete | `DELETE /api/vcenter/namespaces/instances/{namespace}` | 204; deletion accepted |
| Ephemeral session close on normal completion | `DELETE /api/session` | 204 |

The vSphere provider also performs its own authenticated SOAP/REST inventory discovery for datacenter, compute cluster, storage policy and content library data sources. Those operations are provider-owned, not custom shell API functions. This is a single-cluster Supervisor workflow, matching script 01; multi-zone creation is outside this module's scope.

| Symptom | Diagnostic step and next action |
| --- | --- |
| Inventory lookup fails during plan | Verify datacenter/cluster scope, policy/library names and account visibility. Resolve inventory before applying. |
| REST 401 or expired session | Check the literal credentials and permissions in the selected root. Terraform creates a session for each operation; inspect an uncertain namespace write before starting another run. |
| Certificate verification fails | Verify certificate trust for all three providers and the configured `insecure_tls` value. |
| Namespace already exists | Inspect identity and import into the correct root before planning. Do not submit duplicate creation. |
| API rejects quota or bindings | Inspect the API error and actual policy, library, VM class and quota constraints. Passing Terraform validation checks syntax/schema, not platform availability. |
| Apply times out or returns an uncertain result | Inspect live namespace and Terraform state before any retry. Recover state/import if creation was accepted. |
| `CONFIGURING` or `ERROR` after apply | Inspect current status and messages; acceptance alone is not completion. |
| Failed apply leaves a session open | The failed-apply fixture showed Terraform can skip ephemeral close. vCenter expires the session; inspect namespace state before retrying. |
| Unexpected replacement | Check namespace and resolved-cluster changes, state ownership and planned actions before proceeding. |

### vCenter and Supervisor changes during apply

vCenter can return additional observed fields, including `config_status`, `messages`, `stats` and access information. It can normalize configured bindings while Supervisor reconciliation is still underway. The module does not use the Kubernetes provider's computed-field mechanism from the VKS template; this is a JSON REST resource whose response is retained in `api_response`. `config_status` is derived from that response.

The create response has no object body, so the resource uses the known namespace name and a subsequent GET. The update payload contains only mutable settings, preserving the distinction between CreateSpec and UpdateSpec. The offline fixture returned an Info-shaped response without a `namespace` field and verified read-back plus an in-place update. Live response normalization, ordering and asynchronous timing still need verification.

If a subsequent plan reports unexpected drift, compare the requested `create_spec` with the live description, storage specifications and VM Service bindings. Do not globally ignore server changes just to suppress a plan: first determine whether the difference is normalization, another owner or an incomplete operation. The module has no readiness waiter and no automatic recovery from an uncertain write. Follow [How to delete the namespace](#how-to-delete-the-namespace) for deliberate removal.

## Output

The following saved files document Terraform operations and observed namespace configuration.

| Namespace | Output | Description |
| --- | --- | --- |
| `dev-namespace` | [DEV Terraform deployment output](terraform-create-vsphere-namespace-x/dev-namespace/terraform-out.txt) | Terminal transcript of initialization, plans, applies, deletion/recreation, and Terraform output values. The final apply reports one namespace resource added, with `config_status = "CONFIGURING"`; reconciliation was still pending in that read-back. |
| `qa-namespace` | [QA Terraform deployment output](terraform-create-vsphere-namespace-x/qa-namespace/terraform-out.txt) | Terminal transcript of initialization, plans, applies, deletion/recreation, and Terraform output values. The final apply reports one namespace resource added, with `config_status = "CONFIGURING"`; reconciliation was still pending in that read-back. |
| `dev-namespace` and `qa-namespace` | [Namespace configuration report](output/document-namespace-configuration-vds.txt) | Read-only vCenter inventory captured on **2026-10-22 at 13:22:56 GMT**. Covers seven visible namespaces, including DEV and QA, and records both as `RUNNING`. Includes placement, descriptions, storage policies and limits, VM classes, content libraries, permissions, quotas, and VLAN network/CIDR information. |

The Terraform files are command transcripts, not captures of `terraform output` alone. They retain intermediate states and typed-command errors. Follow the deployment procedures in this guide when running commands. A successful apply and a completed destroy message must be distinguished from verified platform readiness or final absence.

The shared report was produced by `04-document-namespace-configuration-vds.sh`, a separate read-only collector. Its header records TLS verification disabled, and its final result reports all requested API reads completed. It does not verify connectivity, workload readiness, or Terraform ownership. Embedded absolute paths refer to the original lab checkout; the table links to the copy in this repository.

The inventory report records the requested descriptions and a **512000 MiB (500 GiB) per-policy limit** for DEV and QA. This matches the REST configuration, but the report itself does not identify Terraform state ownership or prove which operation created the observed objects.

These records describe historical activity, not current infrastructure state. No live infrastructure operations were run for this documentation update. See [Outputs and completion](#outputs-and-completion) for the available Terraform values and current-state checks.

## References

- [Native namespace resource](https://registry.terraform.io/providers/vmware/vsphere/latest/docs/resources/namespace)
- [REST resource](https://registry.terraform.io/providers/Mastercard/restapi/latest/docs/resources/object)
- [REST provider](https://registry.terraform.io/providers/Mastercard/restapi/latest/docs)
- [VMware vSphere provider](https://registry.terraform.io/providers/vmware/vsphere/latest/docs) — inventory discovery and provider configuration.
- [Terraform provider inheritance](https://developer.hashicorp.com/terraform/language/modules/develop/providers#implicit-provider-inheritance) — default provider connections passed from roots to this module.
- [Kubernetes provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs) — used by the VKS workflow, not by this namespace module.
- [Local provider](https://registry.terraform.io/providers/hashicorp/local/latest/docs) — used for VKS YAML generation, not configured here.
- [Ephemeral session resource](https://registry.terraform.io/providers/magodo/restful/0.25.2/docs/ephemeral-resources/resource) — session open/close and sensitive output.
- [Terraform ephemeral resources](https://developer.hashicorp.com/terraform/language/block/ephemeral) — temporary provider credentials excluded from state and plans.
