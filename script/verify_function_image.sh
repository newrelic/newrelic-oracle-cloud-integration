#!/bin/bash
# Checks that a function image carries a valid New Relic signature, using cosign.
#
#   script/verify_function_image.sh docker.io/newrelic/beyond-oci-metric-function[:<tag>]@sha256:<digest>
#
# Exits non-zero unless the image's cosign signature verifies against one of the public keys
# published at SIGNING_JWKS_URL. Signatures are not in the public transparency log
# (oci-signer signs with --private-infrastructure), so none is looked up.
#
# Environment:
#   SIGNING_JWKS_URL   JWKS of the oci-signer key that signs this image
set -euo pipefail

ref="${1:-}"
if [[ ! "$ref" =~ ^(docker\.io/[a-z0-9._/-]+)(:[0-9A-Za-z._-]+)?@(sha256:[0-9a-f]{64})$ ]]; then
  echo "Error: expected docker.io/<repository>[:<tag>]@sha256:<digest>, got '$ref'"
  exit 1
fi
# By digest only: the signature is bound to the digest, and the tag adds nothing to check.
image="${BASH_REMATCH[1]}@${BASH_REMATCH[3]}"

if [ -z "${SIGNING_JWKS_URL:-}" ]; then
  echo "Error: SIGNING_JWKS_URL is not set."
  exit 1
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

curl -fsSL --retry 3 -o "$workdir/jwks.json" "$SIGNING_JWKS_URL"

# cosign takes PEM keys; the JWKS lists raw Ed25519 keys. One file per key, so a key rotation
# (old and new key both published) still verifies images signed with either.
python3 -I - "$workdir/jwks.json" "$workdir" <<'EOF'
import base64, json, sys
jwks, out = sys.argv[1], sys.argv[2]
# DER prefix of an Ed25519 SubjectPublicKeyInfo; the 32-byte key follows it.
prefix = bytes.fromhex("302a300506032b6570032100")
count = 0
for key in json.load(open(jwks)).get("keys", []):
    if key.get("kty") != "OKP" or key.get("crv") != "Ed25519":
        continue
    x = base64.urlsafe_b64decode(key["x"] + "=" * (-len(key["x"]) % 4))
    if len(x) != 32:
        continue
    der = base64.encodebytes(prefix + x).decode()
    with open("%s/key-%d.pem" % (out, count), "w") as f:
        f.write("-----BEGIN PUBLIC KEY-----\n" + der + "-----END PUBLIC KEY-----\n")
    count += 1
if not count:
    sys.exit("no Ed25519 keys in " + jwks)
EOF

for key in "$workdir"/key-*.pem; do
  if cosign verify --key "$key" --private-infrastructure "$image" > /dev/null; then
    echo "Verified New Relic signature on $image"
    exit 0
  fi
done
echo "Error: $image has no signature that verifies against $SIGNING_JWKS_URL"
exit 1
