<!--
author: "Julius M. Nicolescu"
date: "October 2026"
description: "Technical comparison of native vSphere provider and REST-based Terraform namespace implementations, including resource ownership, feature coverage, Supervisor discovery, authentication, storage limits, and lifecycle tradeoffs for DEV and QA environments."
keywords: ["VCF", "vSphere", "Supervisor", "Terraform", "Namespaces", "REST API", "Provider comparison"]
lang: en
-->

# Compare the native and REST Terraform vSphere namespace models

Both models manage DEV and QA vSphere namespaces through separate Terraform roots and a shared module. Their main difference is **which provider owns namespace lifecycle and which settings it can manage**.

The native model reduces custom API payload code and waits for namespace configuration during creation. The REST model manages the requested descriptions and **512000 MiB (500 GiB) per-policy storage limit**, which the selected native resource does not expose. Neither model is better for every requirement.

**Scope:** VCF 9.1.1 lab configurations reviewed on 2026-10-22. This comparison describes the checked-in implementations and the versions recorded in their READMEs, not every future provider release. It does not establish live namespace provisioning success.

## GitHub repository

**Repository:** [github.com/jmnicolescu/terraform-vks](https://github.com/jmnicolescu/terraform-vks)

Access the Terraform projects, deployment guides, and captured output files in this repository.

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

## Reference implementations

| Model | Directory and deployment guide | Managed Terraform resource |
| --- | --- | --- |
| Native lifecycle with REST discovery | [terraform-create-vsphere-namespace](Readme-create-vsphere-namespace.md) | `vsphere_namespace.namespace` |
| REST lifecycle | [terraform-create-vsphere-namespace-x](Readme-create-vsphere-namespace-x.md) | `restapi_object.namespace` |

Each directory contains `dev-namespace`, `qa-namespace` and `modules/vsphere-namespace`. Each root owns its connection settings, lock file and independent state. The `-x` directory preserves an alternative implementation; it is not a second deployment stage.

## Providers and ownership

| Responsibility | Native model | REST model |
| --- | --- | --- |
| Namespace create, read, update and delete | `vmware/vsphere` 2.17.1 | `Mastercard/restapi` 2.0.1 |
| Storage-policy and content-library discovery | `vmware/vsphere` | `vmware/vsphere` |
| Placement discovery | `magodo/restful` reads Supervisor summaries by name | `vmware/vsphere` resolves datacenter and compute cluster by name |
| Automatic temporary REST session | `magodo/restful` 0.25.2, for discovery | `magodo/restful` 0.25.2, for namespace operations |
| Provider count | Two | Three |
| Version selection | Exact pins: vSphere 2.17.1 and restful 0.25.2 | Constraints: vSphere `~> 2.16`, restapi `~> 2.0`, restful `~> 0.25.2`; lock files record the versions above |

The native provider constructs namespace requests internally. The REST module constructs CreateSpec and UpdateSpec JSON and configures the HTTP methods and paths itself. Native therefore means provider-owned namespace lifecycle; it does not mean that the workflow makes no REST calls.

Both roots require Terraform >= 1.10 for ephemeral authentication. Both need vCenter connectivity during planning, suitable inventory and namespace permissions, and trusted certificates when TLS verification is enabled. Neither workflow requires shell sourcing, environment exports, manual curl login or copied session tokens.

## Feature comparison

| Capability | Native model | REST model |
| --- | --- | --- |
| Create `dev-namespace` and `qa-namespace` | Yes | Yes |
| Set `Dev Namespace` / `QA Namespace` descriptions | Not exposed; these descriptions are not applied | Managed through `description` |
| Assign existing storage policies | Yes | Yes |
| Enforce the requested 512000 MiB limit | Not exposed; this workflow does not configure the limit | `storage_limit_mib = 512000` applies to each assigned policy |
| Bind VM classes and content libraries | Yes | Yes |
| Require a hardcoded Supervisor UUID | No | No |
| Import an existing namespace | No importer in native provider 2.17.1 | Import procedure documented in the REST guide; live import unverified |
| Wait for namespace creation readiness | Provider polls for `RUNNING` every 15 seconds, up to two minutes | No readiness waiter; reads the returned status |
| Wait for update completion or final deletion | No | No |
| Expose observed `config_status` | No | Yes; last observed value, not continuous monitoring |
| Expose the desired API payload | No; provider builds requests internally | `create_spec` output |
| Rename or change placement | Not supported as an ordinary update in this version | Namespace/resolved-cluster change forces replacement |

The REST limit is **per policy**, not a single aggregate namespace limit. Assigning multiple policies applies 512000 MiB to each. Neither module manages Supervisor creation, shared Supervisor image-library settings, user access grants, namespace network overrides or VKS clusters.

## How both models avoid a hardcoded Supervisor UUID

The native resource requires a Supervisor UUID, but provider 2.17.1 has no Supervisor data source. The root supplies `supervisor_name = "lab-supervisor"`. The shared module reads `GET /api/vcenter/namespace-management/supervisors/summaries`, matches `items[].info.name`, and extracts `supervisor`. It rejects missing or duplicate matches, malformed inventory and invalid UUIDs before passing `local.supervisor_id` to the native resource.

The REST model takes a different path. It supplies `datacenter_name` and `cluster_name`, resolves the compute-cluster inventory ID through native vSphere data sources, and sends that ID as `cluster` in the single-cluster namespace CreateSpec. This API contract does not require the module to supply a Supervisor UUID. A compute-cluster inventory ID and a Supervisor UUID are different identifiers.

Both keep readable placement names in configuration. Native lookup removes a manually maintained UUID while retaining the API's UUID requirement. REST uses the cluster-based creation contract instead. Neither mechanism migrates an existing namespace when the selected infrastructure changes, and the REST module is explicitly scoped to single-cluster creation.

## API contracts and authentication

| Operation | Native model | REST model |
| --- | --- | --- |
| Create namespace | Provider sends `POST /api/vcenter/namespaces/instances/v2` | Module configures `POST /api/vcenter/namespaces/instances` |
| Read namespace | Provider uses `GET /api/vcenter/namespaces/instances/v2/{namespace}` | Module configures `GET /api/vcenter/namespaces/instances/{namespace}` |
| Update namespace | Provider sends binding changes with `PATCH /api/vcenter/namespaces/instances/{namespace}` | Module sends mutable settings with the same PATCH endpoint |
| Delete namespace | `DELETE /api/vcenter/namespaces/instances/{namespace}` | Same endpoint |
| Temporary REST login / logout | `POST /api/session` / `DELETE /api/session`, for discovery | Same endpoints, for lifecycle requests |

Create, update and delete return acceptance responses; HTTP 204 alone does not prove reconciliation is complete. Native adds a creation waiter, but neither implementation waits for updates or final deletion. Check the resulting configuration and removal tasks in vSphere Client.

Both use existing private root `terraform.tfvars` files and ephemeral REST sessions. Session tokens are excluded from state and saved plans; inventory and managed-resource information remain in state. Normal logout is automatic, but documented failure tests show Terraform can skip ephemeral cleanup. The native vSphere provider also manages its own authentication.

## Advantages and tradeoffs

**Choose native lifecycle when the supported bindings cover the requirement.** Its advantages are fewer providers, less module-owned JSON and endpoint logic, and a built-in creation readiness check. Provider maintainers own the namespace request implementation. The tradeoff is dependence on the selected schema: descriptions and storage limits remain unmanaged, import is unavailable, and the two-minute creation waiter can time out after vCenter has accepted creation.

**Choose REST lifecycle when descriptions, per-policy limits or adoption of an existing namespace are required.** It represents the original DEV/QA settings and exposes the desired payload and observed configuration status. Its import support offers a recovery/adoption path unavailable in the selected native version. The tradeoff is more integration code: the module maintains payload fields, endpoint contracts, response interpretation and replacement rules. It has no readiness waiter, and live import and lifecycle behavior still need validation.

REST's explicit replacement rule makes identity changes visible in a plan, but replacement deletes the old namespace and can remove workloads. Native 2.17.1 does not mark name/Supervisor changes as replacements, while its update implementation handles bindings only. An apparent in-place native identity change must not be treated as a supported rename or move.

For the **original requirement including both descriptions and the 512000 MiB limit**, the REST model is the more complete implementation. The native model is appropriate only if those settings are deliberately outside this Terraform workflow's requirements. The default directory name does not make its feature coverage equivalent to the REST alternative.

## Operating flow and state ownership

Select one implementation and one namespace root, then follow its linked deployment guide. Both use the same simple sequence: `terraform init`, `terraform validate`, `terraform plan`, and `terraform apply`. Authentication and inventory discovery run automatically. Literal Terraform settings were initially copied from `00-vcf9-env.sh`; later changes to that Bash file are not automatically imported.

Both models delete their managed namespace when `terraform destroy` is run, with workload consequences. Remove Terraform-managed VKS clusters through their own states first and verify cleanup. After namespace destroy, verify actual absence in vCenter; an empty Terraform state is not proof that asynchronous deletion finished. Referenced Supervisor infrastructure, policies and libraries are not owned by these namespace resources.

**Do not manage the same namespace with both models.** Their resource types and state schemas differ. Renaming a directory, copying state or changing a resource address does not migrate ownership. Existing REST-managed namespaces should retain that owner unless a separate migration procedure has been designed; the pinned native resource cannot import them. After an uncertain write, inspect the live object and state before repeating any mutation.

## Validation and evidence boundaries

The source READMEs record the following checks from 2026-10-22:

| Evidence | Native model | REST model |
| --- | --- | --- |
| Initialization and validation | Both roots passed | Both roots passed |
| Offline fixtures | Discovery success/failure, authentication and module mapping; native lifecycle mocked | Authentication, payloads, read-back, mutable updates, deletion and validation against localhost fixtures |
| Live evidence | Targeted DEV Supervisor discovery plan only; successful lookup and normal session close | No live plan, apply, import, destroy or readiness verification recorded |
| Live namespace lifecycle established | No | No |

This comparison was checked against the local module definitions and both deployment guides. No infrastructure operations were run to write it. Provider upgrades require a fresh schema and behavior review; these tradeoffs may change when later releases add fields, data sources or import support.

## References

- [Native deployment guide](Readme-create-vsphere-namespace.md)
- [REST deployment guide](Readme-create-vsphere-namespace-x.md)
- [Native shared module](terraform-create-vsphere-namespace/modules/vsphere-namespace/main.tf)
- [REST shared module](terraform-create-vsphere-namespace-x/modules/vsphere-namespace/main.tf)

