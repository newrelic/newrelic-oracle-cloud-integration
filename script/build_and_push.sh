#!/bin/bash

# --- Configuration Variables ---
# Get values from environment variables passed by the CI/CD pipeline
# It is critical that OCI_AUTH_TOKEN is passed securely via GitHub Secrets.
oci_auth_token="${ORACLE_AUTH_TOKEN}"
# Get function version
function_build_version="${FUNCTION_BUILD_VERSION}"
# Mode and Region are now first and second arguments respectively
MODE=${1:-"full"} # First argument: "build-only", "full" (push to OCIR) or "dockerhub". Defaults to "full".
REGION=${2} # Second argument: The OCI region (only used by "full").

tenancy_namespace="${OCI_TENANCY_NAMESPACE}"
repository_name="${REPOSITORY_NAME:-newrelic-metrics-integration/oci-metrics-forwarder}"
image_name="${IMAGE_NAME:-oci-metrics-forwarder}"
image_tag="${IMAGE_TAG:-latest}"
username="${OCI_USERNAME}"
dockerhub_repository="${DOCKERHUB_REPOSITORY:-newrelic/oci-metrics-forwarder}"

# Debug: Print the function version
echo "FUNCTION_BUILD_VERSION: ${function_build_version}"

# Validate essential environment variables are set
if [ "${MODE}" == "full" ]; then
  if [ -z "${oci_auth_token}" ]; then
    echo "Error: ORACLE_AUTH_TOKEN environment variable is not set."
    exit 1
  fi
  if [ -z "${tenancy_namespace}" ]; then
    echo "Error: OCI_TENANCY_NAMESPACE environment variable is not set."
    exit 1
  fi
  if [ -z "${username}" ]; then
    echo "Error: OCI_USERNAME environment variable is not set."
    exit 1
  fi
fi
if [ "${MODE}" == "dockerhub" ]; then
  if [ -z "${DOCKERHUB_USERNAME}" ] || [ -z "${DOCKERHUB_TOKEN}" ]; then
    echo "Error: DOCKERHUB_USERNAME and DOCKERHUB_TOKEN environment variables must be set."
    exit 1
  fi
  if [ -z "${function_build_version}" ]; then
    echo "Error: FUNCTION_BUILD_VERSION environment variable is not set."
    exit 1
  fi
fi

echo "--- Starting Docker Image Build and Push Automation (Mode: ${MODE}, Region: ${REGION}, Version: ${function_build_version}) ---"

# --- Build Phase ---
echo "1. Building Docker image..."
# Functions run on GENERIC_X86, and customer stacks copy the linux/amd64 image.
docker build --platform linux/amd64 --build-arg FUNCTION_BUILD_VERSION="${function_build_version}" -t "${image_name}:${image_tag}" newrelic-metrics-function/

if [ $? -ne 0 ]; then
    echo "Error: Docker image build failed."
    exit 1
fi

if [ "${MODE}" == "build-only" ]; then
    echo "Build-only mode: Image built successfully, skipping tag and push."
    exit 0 # Exit successfully after build in build-only mode
fi

# Customer stacks copy the image from Docker Hub into their own Container Registry.
if [ "${MODE}" == "dockerhub" ]; then
    echo "2. Tagging and pushing ${dockerhub_repository}:${function_build_version} and :latest to Docker Hub..."
    echo "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USERNAME}" --password-stdin || { echo "Error: Docker Hub login failed."; exit 1; }
    for tag in "${function_build_version}" latest; do
        docker tag "${image_name}:${image_tag}" "${dockerhub_repository}:${tag}" || { echo "Error: Docker image tagging failed."; exit 1; }
        docker push "${dockerhub_repository}:${tag}" || { echo "Error: Docker image push failed."; exit 1; }
    done
    echo "--- Docker Hub push completed successfully ---"
    exit 0
fi

# --- Tag and Push Phase (Only if not in build-only mode) ---

# Validate region is set for push operations
if [ -z "${REGION}" ]; then
  echo "Error: Region is required for push operations."
  exit 1
fi

echo "2. Tagging Docker image..."
docker tag "${image_name}:${image_tag}" "${REGION}.ocir.io/${tenancy_namespace}/${repository_name}:${image_tag}"

if [ $? -ne 0 ]; then
    echo "Error: Docker image tagging failed."
    exit 1
fi

echo "3. Logging in to OCI Container Registry: ${REGION}.ocir.io..."
echo "${oci_auth_token}" | docker login "${REGION}.ocir.io" -u "${tenancy_namespace}/${username}" --password-stdin

if [ $? -ne 0 ]; then
    echo "Error: Docker login to OCIR failed."
    exit 1 # Ensure this exit is present for login failure
fi
echo "Successfully logged in to OCIR."

# 4. Push the Docker image to the OCI Container Registry
echo "4. Pushing Docker image..."
docker push "${REGION}.ocir.io/${tenancy_namespace}/${repository_name}:${image_tag}"

if [ $? -ne 0 ]; then
    echo "Error: Docker image push failed."
    exit 1
fi
echo "Successfully pushed Docker image to OCIR."

echo "--- Docker Image Build and Push Automation Completed Successfully ---"
