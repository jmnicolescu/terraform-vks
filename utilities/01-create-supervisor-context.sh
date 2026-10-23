#!/usr/bin/env bash
# ------------------------------------------------------------------------------------------------------
# Script Name : 01-create-supervisor-context.sh
# VCF Version : 9.1.1
# Description : Create or recreate and activate the local VCF CLI Supervisor context.
# Environment : SUPERVISOR_API_ENDPOINT, VCF_CLI_VSPHERE_USERNAME
# Requirements: Bash, VCF CLI, Supervisor API connectivity.
# Authentication: vSphere SSO Login
# Usage       : ./01-create-supervisor-context.sh
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

CONTEXT_NAME="supervisor"

# Verify that both VCF CLI and kubectl are installed and accessible in the system PATH.
for cmd in vcf kubectl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: $cmd is not installed or is not available in the system PATH." >&2
    echo "Please install $cmd and ensure it is accessible before proceeding." >&2
    exit 1
  fi
done

# Recreate the local Supervisor context, list contexts, and activate the Supervisor.
vcf context delete "$CONTEXT_NAME" -y

# Create Supervisor context.
echo "Creating $CONTEXT_NAME context..."

vcf context create "$CONTEXT_NAME" \
  --endpoint "$SUPERVISOR_API_ENDPOINT" \
  --username "$VCF_CLI_VSPHERE_USERNAME" \
  --insecure-skip-tls-verify \
  --type k8s \
  --auth-type basic

# Activate the VKS workload cluster context.
echo "Activating VKS context: ${CONTEXT_NAME}"

vcf context use "${CONTEXT_NAME}"

# Display available VCF CLI contexts.
vcf context list

# Validate connectivity to the VKS workload cluster.
echo "Verifying Kubernetes cluster connectivity..."
kubectl get nodes

echo "SUCCESS: ${CONTEXT_NAME} context configured successfully."

