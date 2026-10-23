<!--
author: "Julius M. Nicolescu"
date: "October 2026"
description: "Technical guide to creating and managing DEV and QA vSphere namespaces with the native VMware vSphere Terraform provider, reusable modules, Supervisor discovery, storage policies, VM classes, and independent environment state."
keywords: ["VCF", "vSphere", "Supervisor", "Terraform", "Namespaces", "vSphere provider"]
lang: en
-->

# Create vSphere namespaces with Terraform — native provider

## GitHub repository

**Repository:** [github.com/jmnicolescu/terraform-vks](https://github.com/jmnicolescu/terraform-vks)

Access the Terraform projects, deployment guides, and captured output files in this repository.

## Contents

- [Requirements: Supervisor connection](#requirements-supervisor-connection)
- [GitHub repository](#github-repository)
- [Tested environment and versions](#tested-environment-and-versions)
- [Prerequisites](#prerequisites)
- [Directory structure and configuration](#directory-structure-and-configuration)
- [Why REST discovery is needed and how we avoid hardcoded Supervisor UUIDs](#why-rest-discovery-is-needed-and-how-we-avoid-hardcoded-supervisor-uuids)
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

This project creates and manages `dev-namespace` and `qa-namespace` using the native `vsphere_namespace` resource from **`vmware/vsphere`**, with automatic Supervisor discovery by name. It retains the separate roots and reusable-module structure of the [VKS Terraform workflow](Readme-create-vks-cluster.md).

| Component | Version or scope |
| --- | --- |
| Target VMware Cloud Foundation | `9.1.1.0-545627-2026-09`; repository target, not a live-test claim |
| Terraform CLI used locally | `1.16.6` (`darwin_arm64`) |
| Required Terraform | `>= 1.10.0`, for ephemeral credential inputs |
| Namespace provider | `vmware/vsphere`, pinned to `2.17.1` |
| Discovery provider | `magodo/restful`, pinned to `0.25.2`; authentication and GET lookup only |
| Managed resource | `vsphere_namespace` |
| Namespace contract | vCenter namespace V2 creation, using the UUID discovered from the configured Supervisor name |

The [DEV lock file](terraform-create-vsphere-namespace/dev-namespace/.terraform.lock.hcl) and [QA lock file](terraform-create-vsphere-namespace/qa-namespace/.terraform.lock.hcl) record the selected provider and checksums. The installed schema and [version-specific source](https://github.com/vmware/terraform-provider-vsphere/blob/v2.17.1/vsphere/resource_vsphere_namespace.go) were inspected. Newer code on the provider's main branch has different capabilities; this README describes the pinned release.

The purpose is to describe each namespace in Terraform, review a plan, apply it, and later delete the namespace through the same state. A shared module keeps resource definition, input validation and inventory lookups in one place. Each root owns deployment settings, provider connection and independent state; the module is local Terraform code, not another deployed service.

We chose the native resource to simplify the operational flow. The vSphere provider authenticates using the configured username/password, discovers storage policies and content libraries, and performs namespace lifecycle operations. The module uses `magodo/restful` only for automatic login, a read-only Supervisor lookup and normal logout. Namespace lifecycle remains native. No manual token, curl command or shell-sourcing step is required.

| Decision | Reason and consequence |
| --- | --- |
| Keep native namespace lifecycle | `vmware/vsphere` manages namespaces and discovers policies/libraries. |
| Use `vsphere_namespace` | Namespace operations are implemented by the provider rather than custom REST payloads. |
| Discover Supervisor by name | Provider 2.17.1 has no Supervisor data source. A module-level REST data source requires exactly one matching name and a valid UUID. |
| Authenticate discovery automatically | An ephemeral session supplies the lookup header and closes normally; its token is excluded from state and plans. |
| Pin `2.17.1` | Lifecycle behavior and limitations were checked against that release. Review changes before upgrading. |
| Omit description and storage limit inputs | The native resource exposes neither field. The requested descriptions and `512000 MiB` limit are **not applied by this workflow**. |
| Retain the REST implementation separately | [terraform-create-vsphere-namespace-x](Readme-create-vsphere-namespace-x.md) preserves the full-field alternative and its original module. |

The two implementations are alternatives. Their states are not interchangeable, and the same namespace must never be managed by both. Renaming the old directory did not migrate any resource into native state or change infrastructure.

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

- Terraform >= 1.10 and reachable vCenter. `terraform init` installs the two locked providers.
- An existing operational Supervisor, storage policies, VM classes and content libraries. Their names and identifiers are configuration, not proof of live availability.
- A vCenter account with inventory visibility and namespace configuration permissions. Exact role composition has not been verified live.
- Private root `terraform.tfvars` files. Both were populated from the existing literal lab connection settings; they are already available in this checkout and excluded from commits.
- TLS settings matching the lab. `insecure_tls = true` is retained from the existing configuration; use `false` with a trusted vCenter certificate.
- Namespace names not already managed elsewhere. Native namespace import is **not supported in provider 2.17.1**; see Usage before attempting an existing target.

Supervisor-wide Kubernetes library bindings, network configuration, access grants and VKS clusters are outside this module. It binds existing libraries and VM classes to namespace VM Service. Both namespaces may share the Supervisor; this module does not take ownership of shared Supervisor image settings.

## Directory structure and configuration

This guide is in the repository root, alongside `terraform-create-vsphere-namespace/`.

```text
terraform-create-vsphere-namespace/
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

`terraform-create-vsphere-namespace-x/` contains the preserved REST workflow with the same DEV/QA/module organization. New native roots start with their own state; old state and plans were not copied. The roots have `auth.tf` for automatic discovery authentication; there is no shell helper or cleanup script. The lookup provider does not own namespace lifecycle resources.

### Select the namespace

| Setting | DEV | QA |
| --- | --- | --- |
| Root directory | `dev-namespace` | `qa-namespace` |
| Namespace name | `dev-namespace` | `qa-namespace` |
| Supervisor name | `lab-supervisor` | Same |
| Storage policy | `vSAN Default Storage Policy` | Same |
| VM Service library | `vkr-content-library` | Same |
| VM classes | `best-effort-small`, `best-effort-medium`, `best-effort-large`, `best-effort-xlarge` | Same |
| Description / policy limit | Not managed | Not managed |

The shared module resolves `lab-supervisor` from live vCenter summaries during planning. It matches `items[].info.name` and reads `supervisor`. Missing names, duplicate matches, malformed inventory and invalid UUIDs stop the plan. No literal UUID or saved report is used at runtime.

| File | Purpose |
| --- | --- |
| [DEV main.tf](terraform-create-vsphere-namespace/dev-namespace/main.tf) / [QA main.tf](terraform-create-vsphere-namespace/qa-namespace/main.tf) | Native connection, provider requirements, module inputs and outputs |
| [DEV variables.tf](terraform-create-vsphere-namespace/dev-namespace/variables.tf) / [QA variables.tf](terraform-create-vsphere-namespace/qa-namespace/variables.tf) | vCenter connection and sensitive ephemeral credential inputs |
| [DEV auth.tf](terraform-create-vsphere-namespace/dev-namespace/auth.tf) / [QA auth.tf](terraform-create-vsphere-namespace/qa-namespace/auth.tf) | Automatic login, authenticated lookup provider and normal logout |
| Each root's private `terraform.tfvars` | Literal hostname, username, password and TLS setting |
| Each root's `.terraform.lock.hcl` | Provider version and package checksums |
| [Module main.tf](terraform-create-vsphere-namespace/modules/vsphere-namespace/main.tf) | Supervisor/policy/library discovery, lookup validation and the native resource |
| [Module variables.tf](terraform-create-vsphere-namespace/modules/vsphere-namespace/variables.tf) | Inputs and local validation |
| [Module versions.tf](terraform-create-vsphere-namespace/modules/vsphere-namespace/versions.tf) | Terraform and provider requirements |
| [Module outputs.tf](terraform-create-vsphere-namespace/modules/vsphere-namespace/outputs.tf) | Namespace identity, Supervisor UUID and assigned policy IDs |

| Module input | Required/default | Meaning |
| --- | --- | --- |
| `namespace_name` | Required | Lowercase DNS label, 1–63 characters |
| `supervisor_name` | Required | Exact existing Supervisor name; must resolve to one UUID |
| `storage_policy_names` | Required | Nonempty list of existing policy names without duplicates |
| `content_library_names` | `[]` | Existing VM Service library names |
| `vm_classes` | `[]` | Existing VM class names |

Root connection values are `vcenter`, `vcenter_user`, `vcenter_password` and `insecure_tls`. Credentials are marked sensitive and ephemeral, so those input values are not persisted in Terraform state or saved plans. Keep the already-populated local connection files private and do not enable credential-bearing debug logs. Later credential changes belong in the selected root's `terraform.tfvars`; Terraform does not synchronize it with `00-vcf9-env.sh` (original lab configuration, not included in this export).

### Namespace storage policy and limit

The native resource assigns the configured storage-policy IDs. It does **not** expose per-policy storage limits or a namespace description. Therefore this workflow does not apply `STORAGE_LIMIT_MIB="512000"`, `Dev Namespace` or `QA Namespace` from 00. It does not claim a 500 GiB quota.

The effective limit is determined by existing platform configuration and behavior. Check it in vSphere Client before workload deployment. There is deliberately no unused `storage_limit_mib` variable and no REST patch hidden behind the native resource. If Terraform must manage those extra fields, the preserved REST alternative provides that different contract. Do not combine both lifecycle owners on the same namespace.

## Why REST discovery is needed and how we avoid hardcoded Supervisor UUIDs

The native `vsphere_namespace` resource requires a Supervisor UUID in its `supervisor` argument. Our pinned `vmware/vsphere` provider version **2.17.1** does not provide a Supervisor data source to resolve that UUID from a name. This is a discovery limitation of the selected provider release; namespace creation and deletion are supported by the native resource.

Hardcoding a UUID would require copying an environment-specific identifier into both roots. That value can become stale when a Supervisor is recreated and must be replaced when moving the configuration to another environment. Instead, DEV and QA specify the existing Supervisor's readable name:

```hcl
supervisor_name = "lab-supervisor"
```

We added the lookup to the [shared namespace module](terraform-create-vsphere-namespace/modules/vsphere-namespace/main.tf), so both roots use the same discovery and validation rules. The additional `magodo/restful` provider fills this lookup gap. It does not create, update or delete namespaces in this implementation.

| Responsibility | Provider |
| --- | --- |
| Open and close the discovery session; read Supervisor summaries | `magodo/restful` |
| Resolve storage policies and content libraries; manage namespace lifecycle | `vmware/vsphere` |

Terraform performs the following steps automatically:

1. The root's `auth.tf` opens an ephemeral session with `POST /api/session`, using the configured vCenter credentials. It passes the returned token to the discovery provider as the `vmware-api-session-id` header.
2. The module's `data.restful_resource.supervisors` reads `GET /api/vcenter/namespace-management/supervisors/summaries`.
3. The module matches `items[].info.name` against `supervisor_name` and extracts the matching item's `supervisor` UUID. Postconditions require exactly one matching Supervisor and a valid UUID. Missing or duplicate matches, malformed inventory and invalid UUIDs stop the plan.
4. The module stores the result in `local.supervisor_id` and passes it to `vsphere_namespace.namespace.supervisor`. Terraform's dependency on the lookup ensures the native resource receives the discovered identifier.
5. Terraform normally closes the ephemeral discovery session with `DELETE /api/session`. The token is excluded from plans and state; the discovered inventory is ordinary data-source state. Terraform can skip session cleanup on some error paths, leaving the session to expire in vCenter.

We therefore removed the **hardcoded UUID input**, not the UUID requirement in the vCenter API. The module obtains the required UUID from live inventory using the configured name. There is no manual session-ID retrieval, curl command, shell sourcing or separate discovery step: the workflow remains `terraform init`, `terraform plan`, then `terraform apply`.

This lookup does not migrate an existing namespace to a different Supervisor. If the resolved UUID changes, review the identity-change limitations in [Namespace changes and upgrades](#namespace-changes-and-upgrades) before applying.

## How the shared module calls work

The selected root chooses **where to connect** and **which namespace and bindings to request**. The shared module resolves Supervisor, policy and library IDs and manages the native resource. Edit root inputs for one deployment; edit the module only for behavior intended for every caller.

### Connect the module to vCenter

The native provider handles namespace lifecycle:

```hcl
provider "vsphere" {
  vsphere_server       = var.vcenter
  user                 = var.vcenter_user
  password             = var.vcenter_password
  allow_unverified_ssl = var.insecure_tls
}
```

Each root's `auth.tf` provides the authenticated lookup connection:

```hcl
provider "restful" {
  alias    = "session"
  base_url = "https://${var.vcenter}"
  client = {
    tls_insecure_skip_verify = var.insecure_tls
  }
}

ephemeral "restful_resource" "vcenter_session" {
  provider             = restful.session
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

provider "restful" {
  base_url = "https://${var.vcenter}"
  client = {
    tls_insecure_skip_verify = var.insecure_tls
  }
  header = {
    "vmware-api-session-id" = ephemeral.restful_resource.vcenter_session.sensitive_output
  }
}
```

`restful.session` opens a session with the private root credentials. Its sensitive ephemeral response configures the default `restful` provider. The module inherits default `vsphere` and `restful` connections; the session alias stays in the root. No token is passed as a module input.

Terraform opens the lookup session before reading inventory and closes it on normal completion. `$(body)` is the provider's response substitution, not shell code. The session token and credential inputs are ephemeral; the non-secret inventory is ordinary data-source state. No retry block is configured, and this discovery provider has no configurable request-timeout option. Error paths can skip ephemeral close, as observed in fixtures; those sessions remain until vCenter expires them. Native lifecycle authentication remains separately managed by `vmware/vsphere`.

### Supply the desired namespace settings

DEV uses:

```hcl
module "vsphere_namespace" {
  source = "../modules/vsphere-namespace"

  namespace_name        = "dev-namespace"
  supervisor_name       = "lab-supervisor"
  storage_policy_names  = ["vSAN Default Storage Policy"]
  content_library_names = ["vkr-content-library"]
  vm_classes            = ["best-effort-small", "best-effort-medium", "best-effort-large", "best-effort-xlarge"]
}
```

`module "vsphere_namespace"` is the Terraform module instance name. The actual namespace name comes from `namespace_name`. `source` selects the shared module relative to either root, and each input maps to a corresponding module variable.

`supervisor_name` selects the existing Supervisor; its discovered UUID controls placement. Storage-policy and library names are resolved through native data sources; VM class names are passed directly. These references must already be available in the target environment.

### From inputs to a configured namespace

The module's single managed resource is:

```hcl
resource "vsphere_namespace" "namespace" {
  name             = var.namespace_name
  supervisor       = local.supervisor_id
  storage_policies = [for name in sort(var.storage_policy_names) : data.vsphere_storage_policy.namespace[name].id]

  vm_service {
    content_libraries = [for name in sort(var.content_library_names) : data.vsphere_content_library.namespace[name].id]
    vm_classes        = sort(var.vm_classes)
  }
}
```

Its full address is `module.vsphere_namespace.vsphere_namespace.namespace`. Terraform reads summaries through `data.restful_resource.supervisors`, validates one exact name match and UUID format, and passes `local.supervisor_id` to the native resource. It also resolves policy/library IDs. Lookup failures stop before namespace creation. On creation, provider 2.17.1 submits the V2 namespace CreateSpec and polls every 15 seconds for up to two minutes for `config_status = RUNNING`, then reads configured bindings.

These wait details come from the pinned provider source, not a live deployment test. A timeout can occur after vCenter has accepted creation; inspect the namespace before another mutation. Namespace configuration reaching RUNNING does not establish VKS or application readiness.

## Create DEV vSphere namespace

The private connection files are already populated. From the repository root (`terraform-vks/`):

```bash
cd terraform-create-vsphere-namespace/dev-namespace
terraform init
terraform validate
terraform plan
terraform apply
```

Review the plan and confirm apply. Native and lookup authentication are automatic. `terraform plan` requires live inventory access but does not request namespace creation.

To use a saved plan:

```bash
terraform plan -out=namespace.tfplan
terraform apply namespace.tfplan
```

Review before applying: saved-plan apply does not ask for another confirmation. Keep the private connection file available so Terraform can obtain ephemeral credential inputs at apply time.

**Existing namespaces:** provider 2.17.1 registers no importer for `vsphere_namespace`. There is no supported `terraform import` command for this resource in this version. Do not run a duplicate create, copy REST state, or simply rename the REST resource address to native. If a namespace already exists, keep its existing owner and resolve adoption separately before using this root. No existing namespace is deleted or migrated by this setup work.

## Namespace changes and upgrades

The same native resource manages supported binding changes:

| Change | Input | Scope |
| --- | --- | --- |
| Assign storage policies | `storage_policy_names` | Desired policy IDs; no per-policy limit |
| Assign VM classes | `vm_classes` | Namespace VM Service classes |
| Assign content libraries | `content_library_names` | Namespace VM Service libraries |
| Change description or storage limit | Unsupported | No native input exists |
| Rename namespace or change Supervisor | Unsupported as an ordinary update in this version | Keep identity inputs fixed after creation |
| Upgrade provider | Version pin and lock files | Tooling change; review release behavior first |

After editing supported inputs in the selected root:

```bash
terraform plan
terraform apply
```

Provider 2.17.1 sends updates for policy/VM Service bindings but does not wait for them to finish. Verify the resulting assignments and status in vSphere Client. Empty-list removal and platform-specific constraints require live validation; do not assume an omitted or empty configuration clears every existing binding.

Discovery prevents stale configured IDs but does not implement migration. A recreated Supervisor or changed `supervisor_name` can resolve to a different UUID; inspect that change before applying. The native schema does not mark name/Supervisor changes as replacements, while its update implementation handles only bindings. Therefore an apparent in-place identity change is not a supported rename/move. Stop before applying such a plan. Deliberate deletion/recreation is a separate operation with workload consequences.

Kubernetes upgrades, node counts and worker volumes remain the responsibility of the VKS module. This module also does not upgrade the Supervisor. Changing the provider version should be followed by schema review, validation and fresh plans for both roots.

## Create QA vSphere namespace

[qa-namespace/main.tf](terraform-create-vsphere-namespace/qa-namespace/main.tf) calls the same module with `namespace_name = "qa-namespace"`. QA has its own connection file, state, lock file and plans.

| QA setting | Value |
| --- | --- |
| Namespace | `qa-namespace` |
| Supervisor name | `lab-supervisor` |
| Storage policy | `vSAN Default Storage Policy` |
| VM Service library | `vkr-content-library` |
| VM classes | The same four best-effort classes as DEV |

From the repository root (`terraform-vks/`):

```bash
cd terraform-create-vsphere-namespace/qa-namespace
terraform init
terraform validate
terraform plan
terraform apply
```

Review the QA target before confirming. Run later updates and destruction from this directory. Never copy DEV state or plans into QA. The existing-namespace/import limitation under Usage applies equally to QA. Configuration setup does not deploy the namespace.

## How to delete the namespace

`terraform destroy` deletes the namespace owned by the selected root and its workloads. First remove Terraform-managed VKS clusters through their own VKS configurations and verify their cleanup, so their state is not left pointing to workloads removed with the namespace.

From the repository root (`terraform-vks/`), choose one root:

| Target | Command |
| --- | --- |
| DEV | `cd terraform-create-vsphere-namespace/dev-namespace` |
| QA | `cd terraform-create-vsphere-namespace/qa-namespace` |

Then run:

```bash
terraform plan -destroy
terraform destroy
terraform state list
```

For one existing managed namespace, expect **0 to add, 0 to change, 1 to destroy**. Data sources do not own the referenced storage policies or libraries. Review `module.vsphere_namespace.vsphere_namespace.namespace` and confirm the intended name.

Provider 2.17.1 sends the delete request without polling for final absence. Verify removal and task completion in vSphere Client after Terraform returns. The other root's namespace, Supervisor, storage policies and content libraries remain. A timeout or accepted request is not proof that cleanup finished; inspect state before retrying. Never delete Terraform state as a substitute for deleting infrastructure.

Recreate only after confirmed removal:

```bash
terraform plan
terraform apply
```

## Outputs and completion

Both the module and roots expose:

| Output | Meaning |
| --- | --- |
| `namespace_name` | Configured namespace name |
| `namespace_id` | Provider resource ID; namespace name after successful creation/read |
| `supervisor_id` | Discovered UUID passed to the native resource |
| `storage_policy_ids` | Assigned policy IDs returned by the resource |

From the selected root:

```bash
terraform output
terraform state list
```

The native resource exposes no `config_status` output. Its create waiter checks RUNNING, but updates/deletion have different completion behavior in the pinned release. Inspect current namespace status and task results in vSphere Client; an output ID alone is not proof of current readiness. Workload cluster and application health need their own checks.

To refresh tracked bindings without changing namespace configuration:

```bash
terraform plan -refresh-only
terraform apply -refresh-only
```

### Export the native namespace outputs

This section corresponds to the VKS template's generated-manifest section. The native implementation does not construct a public CreateSpec/YAML output and does not configure `hashicorp/local`. The provider builds API requests internally.

If an output snapshot is needed, export the root outputs explicitly:

```bash
terraform output -json > namespace-outputs.json
chmod 600 namespace-outputs.json
```

The file contains output values and Terraform output metadata. It is not a deployment payload or Kubernetes manifest. Terraform does not manage this manually exported file, and destroy does not remove it. No file-export step is required for deployment.

## API operations and troubleshooting

Namespace lifecycle belongs to `vmware/vsphere`. The module adds `magodo/restful` for read-only Supervisor discovery using automatic ephemeral authentication. There is no shell helper. The namespace operations below are derived from provider 2.17.1 and the bundled vCenter contract. The provider owns exact error/response handling.

| Provider operation | Method and endpoint | Meaning |
| --- | --- | --- |
| Native authentication and inventory | Provider-managed SOAP/REST sessions and policy/library discovery | Native connection and inventory |
| Discovery login | `POST /api/session` | HTTP 201; automatic ephemeral session |
| Supervisor lookup | `GET /api/vcenter/namespace-management/supervisors/summaries` | HTTP 200; validate one exact name match and UUID |
| Discovery logout | `DELETE /api/session` | HTTP 204; normal ephemeral close |
| `CreateNamespaceV2` | `POST /api/vcenter/namespaces/instances/v2` | HTTP 204 accepts creation; provider then waits for RUNNING |
| `GetNamespaceV2` | `GET /api/vcenter/namespaces/instances/v2/{namespace}` | HTTP 200 returns namespace info |
| `UpdateNamespace` | `PATCH /api/vcenter/namespaces/instances/{namespace}` | HTTP 204 accepts binding changes; no update waiter in this version |
| `DeleteNamespace` | `DELETE /api/vcenter/namespaces/instances/{namespace}` | HTTP 204 accepts deletion; no deletion waiter in this version |

| Symptom | Next action |
| --- | --- |
| Authentication or certificate error | Check private root connection values and vCenter trust. No user-supplied session token is needed. |
| Supervisor lookup fails | Check the configured name, inventory permissions and response. Zero or multiple matches are rejected. |
| Policy/library lookup failure | Verify exact names and account visibility. |
| Namespace already exists | Stop duplicate creation. This release cannot import the existing namespace into native state. |
| Creation timeout | Inspect vSphere Client and Terraform state; vCenter may have accepted creation before the two-minute waiter expired. |
| Import reports unsupported | Expected for native resource 2.17.1; do not substitute a REST import address. |
| Plan proposes changing identity | Keep namespace/Supervisor fixed; the native update implementation does not implement rename or move. |
| Description or limit differs from 00 | Expected limitation: these fields are outside the native resource schema. |

An uncertain create can leave an existing namespace without a usable native state entry, and this release lacks import recovery. Resolve the actual object/state situation before taking further action. Do not automatically retry mutations or force-delete workloads to make a plan succeed.

### vCenter and Supervisor changes during apply

The provider reads configured VM Service bindings and storage-policy IDs after creation. vCenter and Supervisor perform the actual reconciliation and can normalize their returned representation. The native schema uses lists in 2.17.1; the module supplies sorted names to keep its own requested ordering deterministic.

There is no Kubernetes computed-field workaround or generic REST drift configuration here. Investigate differences between requested and returned bindings rather than ignoring all changes. Provider main-branch improvements do not establish that they are available in the pinned release.

## Output

The following saved files document Terraform operations and observed namespace configuration.

| Namespace | Output | Description |
| --- | --- | --- |
| `dev-namespace` | [DEV Terraform deployment output](terraform-create-vsphere-namespace/dev-namespace/terraform-out.txt) | Native-provider terminal transcript containing initialization, planning, successful namespace creation, output values, and deletion. The last operation reports `Destroy complete! Resources: 1 destroyed.`; this transcript does not end with a deployed namespace. |
| `qa-namespace` | [QA Terraform deployment output](terraform-create-vsphere-namespace/qa-namespace/terraform-out.txt) | Native-provider terminal transcript containing initialization, planning, successful namespace creation, output values, and deletion. The last operation reports `Destroy complete! Resources: 1 destroyed.`; this transcript does not end with a deployed namespace. |
| `dev-namespace` and `qa-namespace` | [Namespace configuration report](output/document-namespace-configuration-vds.txt) | Read-only vCenter inventory captured on **2026-10-22 at 13:22:56 GMT**. Covers seven visible namespaces, including DEV and QA, and records both as `RUNNING`. Includes placement, descriptions, storage policies and limits, VM classes, content libraries, permissions, quotas, and VLAN network/CIDR information. |

The Terraform files are command transcripts, not captures of `terraform output` alone. They retain intermediate states and typed-command errors. Follow the deployment procedures in this guide when running commands. A successful apply and a completed destroy message must be distinguished from verified platform readiness or final absence.

The shared report was produced by `04-document-namespace-configuration-vds.sh`, a separate read-only collector. Its header records TLS verification disabled, and its final result reports all requested API reads completed. It does not verify connectivity, workload readiness, or Terraform ownership. Embedded absolute paths refer to the original lab checkout; the table links to the copy in this repository.

The shared inventory report also shows descriptions and **512000 MiB (500 GiB) per-policy limits**. These fields are not managed by this native module. Do not attribute them to the native applies or treat this shared report as proof that the native state owns the observed namespaces. The [REST guide](Readme-create-vsphere-namespace-x.md#output) links the separate REST deployment transcripts.

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
