#!/bin/bash
#
# Run the same Trivy vulnerability scan locally that CI runs in
# .github/workflows/repo_level_scan.yml, which delegates to the reusable
# workflow newrelic/.github/.github/workflows/org-level-trivy-scan.yml.
#
# Like the org workflow, this builds the function image and then scans it three
# ways:
#   1. every severity, including vulnerabilities with no fix available
#   2. every severity, fixable only
#   3. fixable only, written to trivy-results.sarif
#
# Only the third pass gates: CI fails the build when a fixable vulnerability is
# found, so this script exits non-zero in that case too.
#
# Requires docker and trivy (brew install trivy).
#
# Environment variables:
#   IMAGE_NAME   image:tag to build and scan (default trivy-local-scan:latest)
#   PLATFORM     build platform (default linux/amd64, matching CI runners)
#   SEVERITY     severities to report (default CRITICAL,HIGH,MEDIUM,LOW,UNKNOWN)
#   SKIP_BUILD   set to 1 to scan an existing IMAGE_NAME instead of rebuilding
#   CA_CERT      PEM file holding an extra trust anchor. Needed only behind a
#                TLS-inspecting proxy, where the base image cannot otherwise
#                reach yum.oracle.com or pypi.org. The certificate is added to
#                a throwaway copy of the build context, never to the Dockerfile
#                that ships in this repository.

set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FUNCTION_DIR="${REPO_ROOT}/newrelic-metrics-function"

image_name="${IMAGE_NAME:-trivy-local-scan:latest}"
platform="${PLATFORM:-linux/amd64}"
severity="${SEVERITY:-CRITICAL,HIGH,MEDIUM,LOW,UNKNOWN}"
sarif_output="${REPO_ROOT}/trivy-results.sarif"

for tool in docker trivy; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Error: ${tool} is not installed or not on PATH."
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "Error: cannot reach the Docker daemon. Start Docker and retry."
  exit 1
fi

# --- Build Phase ---
if [ "${SKIP_BUILD}" != "1" ]; then
  build_context="${FUNCTION_DIR}"
  build_dir=""

  if [ -n "${CA_CERT}" ]; then
    if [ ! -f "${CA_CERT}" ]; then
      echo "Error: CA_CERT is set but ${CA_CERT} does not exist."
      exit 1
    fi
    echo "Staging build context with the extra trust anchor from ${CA_CERT}..."
    build_dir="$(mktemp -d)"
    trap 'rm -rf "${build_dir}"' EXIT
    cp -R "${FUNCTION_DIR}/." "${build_dir}/"
    cp "${CA_CERT}" "${build_dir}/corp-ca.pem"
    # Trust the proxy CA in every stage so microdnf and pip can fetch packages.
    awk '
      { print }
      /^FROM / {
        print "COPY corp-ca.pem /etc/pki/ca-trust/source/anchors/corp-ca.pem"
        print "RUN update-ca-trust extract || true"
        print "ENV REQUESTS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt PIP_CERT=/etc/pki/tls/certs/ca-bundle.crt SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt"
      }
    ' "${FUNCTION_DIR}/Dockerfile" > "${build_dir}/Dockerfile"
    build_context="${build_dir}"
  fi

  echo "1. Building ${image_name} for ${platform}..."
  docker build --platform "${platform}" --pull -t "${image_name}" "${build_context}"

  if [ $? -ne 0 ]; then
    echo "Error: Docker image build failed."
    exit 1
  fi
else
  echo "1. SKIP_BUILD=1, scanning the existing ${image_name}..."
fi

# --- Scan Phase ---
echo
echo "2. All vulnerabilities (including those with no fix available)..."
trivy image --scanners vuln --severity "${severity}" --format table \
  --exit-code 0 "${image_name}"

echo
echo "3. Vulnerabilities with a fix available..."
trivy image --scanners vuln --severity "${severity}" --ignore-unfixed --format table \
  --exit-code 0 "${image_name}"

echo
echo "4. Writing SARIF report for fixable vulnerabilities to ${sarif_output}..."
trivy image --scanners vuln --severity "${severity}" --ignore-unfixed --format sarif \
  --output "${sarif_output}" --exit-code 1 "${image_name}"
scan_status=$?

echo
if [ ${scan_status} -ne 0 ]; then
  echo "--- Trivy found fixable vulnerabilities. CI would fail on this image. ---"
else
  echo "--- No fixable vulnerabilities found. ---"
fi

exit ${scan_status}
