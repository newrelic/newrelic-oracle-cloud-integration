#!/bin/bash
# Signs a published function image through New Relic's OCI signing service (oci-signer).
#
#   script/sign_function_image.sh docker.io/newrelic/beyond-oci-metric-function:<version>@sha256:<digest>
#
# The service holds the private key and writes the cosign signature to Docker Hub itself, as the
# sha256-<digest>.sig tag next to the image, so nothing here needs Docker Hub write access.
# Verify the result with script/verify_function_image.sh.
#
# Environment:
#   OCI_SIGNER_CLIENT     client name registered for this repository in oci-signer
#   NR_CLIENT_ID          system identity client ID allowed to sign for that client
#   NR_PRIVATE_KEY_B64    that system identity's private key (PEM), base64-encoded
set -euo pipefail

SIGNING_URL="https://oci-signer.service.newrelic.com"
# newrelic-auth-cli exchanges the system identity key for a bearer token. Pinned by checksum:
# it runs with the signing credentials.
AUTH_CLI_VERSION="0.7.0"
AUTH_CLI_SHA256="dc850a2a64ccea554e2b02f1b9fc4bd6fda5baac53a557cc8808db1b537527ef"

ref="${1:-}"
if [[ ! "$ref" =~ ^docker\.io/([a-z0-9._/-]+):([0-9A-Za-z._-]+)@(sha256:[0-9a-f]{64})$ ]]; then
  echo "Error: expected docker.io/<repository>:<tag>@sha256:<digest>, got '$ref'"
  exit 1
fi
repository="${BASH_REMATCH[1]}"
tag="${BASH_REMATCH[2]}"
digest="${BASH_REMATCH[3]}"

for name in OCI_SIGNER_CLIENT NR_CLIENT_ID NR_PRIVATE_KEY_B64; do
  if [ -z "${!name:-}" ]; then
    echo "Error: $name is not set."
    exit 1
  fi
done

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

curl -fsSL --retry 3 -o "$workdir/auth-cli.tar.gz" \
  "https://github.com/newrelic/newrelic-auth-rs/releases/download/${AUTH_CLI_VERSION}/newrelic-auth-cli_amd64.tar.gz"
echo "${AUTH_CLI_SHA256}  $workdir/auth-cli.tar.gz" | sha256sum --check --quiet
tar -xzf "$workdir/auth-cli.tar.gz" -C "$workdir"

(umask 077 && echo "$NR_PRIVATE_KEY_B64" | base64 -d > "$workdir/key.pem")
token=$("$workdir/newrelic-auth-cli" authenticate \
  --client-id "$NR_CLIENT_ID" \
  --environment US \
  --private-key-path "$workdir/key.pem" \
  --output-token-format JSON | jq -r '.access_token')
if [ -z "$token" ] || [ "$token" = "null" ]; then
  echo "Error: newrelic-auth-cli returned no access token."
  exit 1
fi
echo "::add-mask::$token"

echo "Signing docker.io/${repository}:${tag}@${digest}"
# A retried request can add a second signature for the same digest; verification accepts any
# valid one, so that is harmless.
jq -n --arg repository "$repository" --arg tag "$tag" --arg digest "$digest" \
  '{registry: "docker.io", repository: $repository, tag: $tag, digest: $digest}' |
  curl -sS --fail-with-body --retry 3 --retry-all-errors \
    -X POST "${SIGNING_URL}/v1/signing/${OCI_SIGNER_CLIENT}/sign" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    --data-binary @-
echo
