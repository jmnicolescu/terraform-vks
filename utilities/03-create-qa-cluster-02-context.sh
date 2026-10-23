#!/usr/bin/env bash
# ------------------------------------------------------------------------------------------------------
# Script Name : 03-create-qa-cluster-02-context.sh
# VCF Version : 9.1.1
# Description : Create or recreate and activate the local VCF CLI cluster context.
# Environment : SUPERVISOR_API_ENDPOINT, VCF_CLI_VSPHERE_USERNAME
# Requirements: Bash, VCF CLI, Supervisor API connectivity.
# Authentication: vSphere SSO Login
# Usage       : ./03-create-qa-cluster-02-context.sh
# ------------------------------------------------------------------------------------------------------

# ------------------------------------------------------------------------------------------------------
# SECURITY WARNING:
# The VCF_CLI_VSPHERE_PASSWORD variable contains a plaintext vCenter SSO password.
# Hardcoding credentials is NOT recommended for production environments.
# Never commit scripts containing passwords to Git repositories or share them publicly.
# Prefer secure credential management or interactive authentication.
# If exposed, rotate the password immediately.
# ------------------------------------------------------------------------------------------------------
# set -euo pipefail

VCF_CLI_VSPHERE_USERNAME='administrator@vsphere.local'
VCF_CLI_VSPHERE_PASSWORD='password'
SUPERVISOR_API_ENDPOINT='https://192.168.197.31'

CLUSTER_NAMESPACE='qa-namespace'
CLUSTER_NAME='qa-cluster-02'

# Verify that both VCF CLI and kubectl are installed and accessible in the system PATH.
for cmd in vcf kubectl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: $cmd is not installed or is not available in the system PATH." >&2
    echo "Please install $cmd and ensure it is accessible before proceeding." >&2
    exit 1
  fi
done

# Recreate the local workload context, list contexts, and activate the selected cluster.
vcf context delete "$CLUSTER_NAME" -y

# Create the VKS workload cluster context.
echo "Creating VKS workload cluster context: $CLUSTER_NAME"

vcf context create "$CLUSTER_NAME" \
  --endpoint "$SUPERVISOR_API_ENDPOINT" \
  --username "$VCF_CLI_VSPHERE_USERNAME" \
  --workload-cluster-namespace "$CLUSTER_NAMESPACE" \
  --workload-cluster-name "$CLUSTER_NAME" \
  --insecure-skip-tls-verify \
  --type k8s \
  --auth-type basic

# Activate the VKS workload cluster context.
echo "Activating VKS context: ${CLUSTER_NAME}:${CLUSTER_NAME}"

vcf context use "${CLUSTER_NAME}:${CLUSTER_NAME}"

# Display available VCF CLI contexts.
vcf context list

# Validate connectivity to the VKS workload cluster.
echo "Verifying Kubernetes cluster connectivity..."
kubectl get nodes

echo "SUCCESS: VKS workload cluster context ${CLUSTER_NAME}:${CLUSTER_NAME} is active."
