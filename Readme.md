<!--
author: "Julius M. Nicolescu"
date: "October 2026"
description: "Technical guide to deploying and managing vSphere Namespaces and VKS Clusters with Terraform, including cluster topology, provider configuration, readiness verification, Kubernetes upgrades, worker scaling, and captured deployment outputs."
keywords: ["VCF", "Supervisor", "VKS", "Kubernetes", "Terraform", "Cluster deployment", "Cluster lifecycle"]
lang: en
-->

# Deploying vSphere Namespaces and VKS Clusters with Terraform

This guide presents three Terraform projects for provisioning vSphere namespaces and deploying VKS clusters on VMware Cloud Foundation 9.1.


## Contents

- [Requirements: Supervisor connection](#requirements-supervisor-connection)
- [Executive summary](#executive-summary)
- [What are we trying to solve?](#what-are-we-trying-to-solve)
- [Technical objectives](#technical-objectives)
- [Project portfolio](#project-portfolio)
- [Project 1: Native vSphere namespace provisioning](#project-1-native-vsphere-namespace-provisioning)
- [Project 2: REST-based vSphere namespace provisioning](#project-2-rest-based-vsphere-namespace-provisioning)
- [Project 3: VKS cluster deployment](#project-3-vks-cluster-deployment)
- [How the projects work together](#how-the-projects-work-together)
- [Configuration and operational boundaries](#configuration-and-operational-boundaries)
- [Documentation library](#documentation-library)
- [Publish documentation assets](#publish-documentation-assets)

## Requirements: Supervisor connection

<p style="color: red;"><strong>IMPORTANT: An active network connection to the Supervisor API is required BEFORE running utilities/01-create-supervisor-context.sh. Connect to the lab network or VPN first. Before running the deployment workflow, the supervisor context must exist, be available, and authenticate successfully to the intended Supervisor.</strong></p>

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

## Executive summary

Deploying vSphere Namespaces and VKS Clusters with Terraform:

- **Create vSphere namespaces with Terraform — native provider:** creates `dev-namespace` and `qa-namespace` using the native `vsphere_namespace` resource from the `vmware/vsphere` provider. [Read the project guide](Readme-create-vsphere-namespace.md).
- **Create vSphere namespaces with Terraform — REST alternative:** creates `dev-namespace` and `qa-namespace` through the vCenter REST API, including namespace descriptions and per-storage-policy limits. [Read the project guide](Readme-create-vsphere-namespace-x.md).
- **Create VKS clusters with Terraform:** creates `dev-cluster-01` and `qa-cluster-02` in their respective vSphere namespaces on an existing Supervisor. [Read the project guide](Readme-create-vks-cluster.md).

The namespace projects provide two alternative methods for creating the same namespace resources. Select the method that meets the required configuration, then use the VKS project to create the clusters.

## What are we trying to solve?

Provisioning a Kubernetes environment involves both platform preparation and cluster configuration. A vSphere namespace needs placement, storage-policy assignments, VM classes, and content-library bindings before it can support the intended workloads. A VKS cluster then needs an explicit Kubernetes release, ClusterClass, node sizing, storage, and network settings.

Manual configuration makes these choices difficult to reproduce and review across DEV and QA. Provider feature differences add another challenge: the selected native namespace resource does not expose every setting required by this lab.

These projects express the desired configuration in Terraform, centralize repeated logic in modules, and make changes inspectable before deployment. The two namespace implementations demonstrate the tradeoff between provider-managed lifecycle behavior and direct control over REST payloads.

## Technical objectives

- **Standardize namespace configuration:** assign existing storage policies, VM classes, and content libraries through reusable modules.
- **Support two namespace methods:** use native lifecycle management where its schema is sufficient, or REST lifecycle management when descriptions and per-policy limits are required.
- **Define repeatable VKS topology:** configure cluster identity, release, ClusterClass, node counts, VM class, storage class, and pod/service CIDRs.
- **Separate environment ownership:** retain independent DEV and QA roots, plans, lock files, and state.
- **Make changes reviewable:** initialize and validate configuration, inspect a plan, apply the intended changes, and verify platform reconciliation.
- **Keep responsibilities explicit:** reference existing infrastructure and distinguish Terraform resource management from workload readiness.

## Project portfolio

| Project | Directory | Purpose and description | Project guide |
| --- | --- | --- | --- |
| Native vSphere namespace provisioning | [`terraform-create-vsphere-namespace/`](terraform-create-vsphere-namespace/) | Creates and manages namespaces through the native `vsphere_namespace` resource, with Supervisor discovery by name and reusable VM/storage bindings. | [Native namespace guide](Readme-create-vsphere-namespace.md) |
| REST-based vSphere namespace provisioning | [`terraform-create-vsphere-namespace-x/`](terraform-create-vsphere-namespace-x/) | Manages namespaces through the vCenter REST API, including descriptions and storage limits that the selected native resource does not expose. | [REST namespace guide](Readme-create-vsphere-namespace-x.md) |
| VKS cluster deployment | [`terraform-create-vks-cluster/`](terraform-create-vks-cluster/) | Deploys and manages VKS Cluster custom resources on the Supervisor, using separate DEV and QA roots and a shared cluster module. | [VKS cluster guide](Readme-create-vks-cluster.md) |

## Project 1: Native vSphere namespace provisioning

This project uses `vmware/vsphere` to own namespace lifecycle through `vsphere_namespace`. It discovers the Supervisor UUID from a configured name using `magodo/restful`, then assigns existing storage policies, VM classes, and content libraries.

Its `dev-namespace/` and `qa-namespace/` roots call the shared `modules/vsphere-namespace/` module. The approach keeps namespace lifecycle requests inside the native provider and includes a provider creation waiter.

**Choose this method when** the exposed namespace bindings satisfy the requirement. In the selected provider version, namespace descriptions and per-policy storage limits are not managed, and namespace import is unavailable. Native lifecycle management still uses REST discovery; it does not eliminate API calls.

Continue with the [project guide](Readme-create-vsphere-namespace.md), [prerequisites](Readme-create-vsphere-namespace.md#prerequisites), and [usage procedure](Readme-create-vsphere-namespace.md#create-dev-vsphere-namespace).

## Project 2: REST-based vSphere namespace provisioning

This project uses `Mastercard/restapi` to manage namespace creation, reads, updates, and deletion. The `vmware/vsphere` provider resolves inventory names, while `magodo/restful` manages temporary authentication sessions.

The shared module constructs the namespace API payload, including descriptions, storage-policy assignments and limits, VM classes, and content-library bindings. The supplied configuration requests **512000 MiB (500 GiB) per storage policy**; this is not an aggregate namespace capacity limit.

**Choose this method when** descriptions, explicit per-policy limits, or the documented import path are required. Its additional flexibility means the module maintains request payloads and endpoint behavior. It reads configuration status but does not wait for namespace readiness. The implementation targets the single-cluster namespace creation contract.

Continue with the [project guide](Readme-create-vsphere-namespace-x.md), [prerequisites](Readme-create-vsphere-namespace-x.md#prerequisites), and [usage procedure](Readme-create-vsphere-namespace-x.md#create-dev-vsphere-namespace). Use the [namespace model comparison](Readme-compare-vsphere-namespace-models.md) for the detailed decision criteria and version-specific limitations.

## Project 3: VKS cluster deployment

This project uses `hashicorp/kubernetes` to manage a `cluster.x-k8s.io/v1beta2` Cluster resource through the Supervisor API. The shared `modules/vks-cluster/` module defines the desired topology; `hashicorp/local` writes the desired manifest to a dated YAML artifact.

| Environment | Terraform root | Target namespace | Cluster name |
| --- | --- | --- | --- |
| DEV | `terraform-create-vks-cluster/dev-cluster-01/` | `dev-namespace` | `dev-cluster-01` |
| QA | `terraform-create-vks-cluster/qa-cluster-02/` | `qa-namespace` | `qa-cluster-02` |

Both supplied roots request three control-plane nodes and three workers. These are desired settings, not confirmed running capacity. The QA directory and cluster are both named `qa-cluster-02`.

The Supervisor, VKS service, Cluster CRD, namespaces, and required classes must already exist. Planning requires Supervisor API access. Applying the Cluster resource starts controller reconciliation; it does not establish that the workload cluster is ready.

Continue with the [project guide](Readme-create-vks-cluster.md), [deployment procedure](Readme-create-vks-cluster.md#create-both-clusters), [readiness checks](Readme-create-vks-cluster.md#4-verify-both-clusters), and [upgrade and capacity guidance](Readme-create-vks-cluster.md#upgrade-and-capacity-management).

## How the projects work together

1. **Prepare the platform.** Confirm the existing Supervisor, VKS service, storage policies, VM classes, libraries, access, and capacity.
2. **Select one namespace method.** Use either the native or REST project for each namespace. The REST alternative is not an additional deployment stage.
3. **Provision and verify namespaces.** Run the chosen DEV and QA roots separately and confirm their required configuration has reconciled.
4. **Deploy VKS clusters.** Run the corresponding cluster roots against those namespaces and verify cluster and node readiness.
5. **Manage subsequent changes through the owning state.** Review fresh plans for capacity or release changes and check the resulting platform state.

The dependency is operational: **existing Supervisor → namespace through either method → VKS cluster**. These separate roots do not automatically pass outputs or establish cross-project Terraform dependencies. Keep namespace names and cluster inputs aligned.

## Configuration and operational boundaries

Namespace roots require Terraform **1.10 or later** for ephemeral authentication; VKS roots declare **1.5 or later**. Follow each project's provider constraints and retain its lock files. Namespace planning needs vCenter connectivity; VKS planning needs an authenticated Supervisor kubeconfig and API discovery.

Keep connection credentials in the established private configuration files. Protect state and saved plans, and do not copy them between deployment roots. Never manage the same namespace through both implementations. Existing resources require a supported adoption or migration procedure; changing directories does not transfer ownership.

The namespace modules do not create the Supervisor, grant user access, configure namespace network overrides, or manage shared Supervisor image-library settings. The VKS module references optional CA Secrets rather than creating them. Coordinate these prerequisites outside the projects.

During removal, delete managed VKS clusters through their own states and verify cleanup before deleting their namespaces. After an uncertain operation, inspect both Terraform state and live resources before submitting another mutation.

## Documentation library

| Page | Use it for |
| --- | --- |
| [Native namespace project](Readme-create-vsphere-namespace.md) | Configuration, native-provider behavior, deployment, outputs, deletion, and API details. |
| [REST namespace project](Readme-create-vsphere-namespace-x.md) | REST payloads, storage limits, deployment, adoption, outputs, and lifecycle behavior. |
| [VKS cluster project](Readme-create-vks-cluster.md) | Cluster prerequisites, deployment, readiness, upgrades, scaling, adoption, and deletion. |
| [Namespace model comparison](Readme-compare-vsphere-namespace-models.md) | Feature differences, provider ownership, tradeoffs, and recorded validation evidence. |


## Publish documentation assets

Run `sudo ./run-upload-files-to-platformlab.sh` on the Platform Lab server from this repository. The script publishes generated documentation and copies supporting assets, preserving their directory structure:

| Local source | Server staging directory | Public directory |
| --- | --- | --- |
| `platformlab-images/` | `/platformlab-images/` | `/imported-images/` |
| `platformlab-docs/` | `/platformlab-docs/` | `/imported-html/` |

The documentation copy preserves nested report paths, including `assets/output/` and Terraform transcripts. Shell scripts (`.sh`) are excluded from both documentation copy stages. Utility links in the READMEs point to GitHub. Regenerate the documentation before uploading to include those updated links.

Generated HTML opens web URLs in the same browser tab outside the WordPress iframe. The adjacent external-link icon opens the URL in a new tab. Regenerate HTML with `bash run-md-to-docs.sh --no-pdf --no-docx` and upload the updated files to publish link-behavior changes.

The uploader rewrites relative `diagrams/` links in staged HTML to their public image URLs. It uses `rsync` when available and `cp` otherwise, without deleting destination files. A missing source directory produces a warning and skips that source sync.

Previously uploaded files are not removed automatically; excluding `.sh` files prevents future copies but does not delete existing server copies.
