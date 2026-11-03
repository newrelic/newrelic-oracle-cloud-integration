"""
Tests for newrelic-metrics-setup/image_signature.py and its use in image_mirror.py.

Run from the repository root:  python3 -m unittest discover tests
"""
import base64
import hashlib
import io
import json
import os
import sys
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "fixtures")
sys.path.insert(0, os.path.join(HERE, "..", "newrelic-metrics-setup"))

import image_mirror  # noqa: E402
import image_signature as sig  # noqa: E402

# A real signature written by oci-signer for a New Relic image, with that key's published JWKS.
REAL_DIGEST = "sha256:a22aeab752e0700a0d7b985b6baac431bd10464f8a78099e09f0d9159958d03b"
REAL_REPOSITORY = "docker.io/newrelic/infrastructure-agent-artifacts"

# RFC 8032 section 7.1, tests 1-3: (secret key, public key, message, signature).
RFC8032 = [
    ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
     "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
     "",
     "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
    ("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
     "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
     "72",
     "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
    ("c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
     "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
     "af82",
     "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"),
]


def _encode_point(point):
    x, y, z, _ = point
    inverse = pow(z, sig._P - 2, sig._P)
    x, y = x * inverse % sig._P, y * inverse % sig._P
    return (y | (x & 1) << 255).to_bytes(32, "little")


def _keypair(seed):
    """Test-only Ed25519 key derivation (RFC 8032 section 5.1.5)."""
    h = hashlib.sha512(seed).digest()
    a = int.from_bytes(h[:32], "little")
    a &= (1 << 254) - 8
    a |= 1 << 254
    return a, h[32:], _encode_point(sig._multiply(a, sig._BASE))


def _sign(seed, message):
    """Test-only Ed25519 signing (RFC 8032 section 5.1.6), to build signatures for edge cases."""
    a, prefix, public = _keypair(seed)
    r = int.from_bytes(hashlib.sha512(prefix + message).digest(), "little") % sig._L
    encoded_r = _encode_point(sig._multiply(r, sig._BASE))
    k = int.from_bytes(hashlib.sha512(encoded_r + public + message).digest(), "little") % sig._L
    return encoded_r + ((r + k * a) % sig._L).to_bytes(32, "little")


TEST_SEED = bytes(range(32))
TEST_KEY = ("test/0", _keypair(TEST_SEED)[2])
OTHER_SEED = bytes(range(1, 33))

DIGEST = "sha256:" + "ab" * 32
REPOSITORY = "docker.io/newrelic/beyond-oci-metric-function"


def payload(digest=DIGEST, reference=REPOSITORY + ":1.42", type_=sig.SIGNATURE_TYPE):
    return json.dumps({
        "critical": {
            "identity": {"docker-reference": reference},
            "image": {"docker-manifest-digest": digest},
            "type": type_,
        },
        "optional": None,
    }).encode()


def layer(data, signature=None, inline=True, seed=TEST_SEED):
    signature = _sign(seed, data) if signature is None else signature
    entry = {
        "mediaType": sig.SIMPLE_SIGNING,
        "digest": "sha256:" + hashlib.sha256(data).hexdigest(),
        "size": len(data),
        "annotations": {sig.SIGNATURE_ANNOTATION: base64.b64encode(signature).decode()},
    }
    if inline:
        entry["data"] = base64.b64encode(data).decode()
    return entry


class FakeRegistry:
    """Serves one signature manifest and its blobs, the way image_mirror.Registry would."""

    def __init__(self, layers=None, manifest=None, blobs=None):
        self.repository = "newrelic/beyond-oci-metric-function"
        self.manifest = manifest if manifest is not None else (
            None if layers is None else {"schemaVersion": 2, "layers": layers})
        self.blobs = blobs or {}
        self.requested = []

    def manifest_digest(self, reference):
        self.requested.append(reference)
        return None if self.manifest is None else "sha256:" + "00" * 32

    def get_manifest(self, reference):
        return image_mirror.OCI_MANIFEST, json.dumps(self.manifest).encode()

    def download_blob(self, digest, path):
        with open(path, "wb") as f:
            f.write(self.blobs[digest])


class Ed25519Test(unittest.TestCase):
    def test_rfc8032_vectors_verify(self):
        for _, public, message, signature in RFC8032:
            self.assertTrue(sig.ed25519_verify(
                bytes.fromhex(public), bytes.fromhex(message), bytes.fromhex(signature)))

    def test_test_signer_reproduces_rfc8032(self):
        # Proves the test-only signer used below is a correct Ed25519 implementation.
        for secret, public, message, signature in RFC8032:
            self.assertEqual(_keypair(bytes.fromhex(secret))[2].hex(), public)
            self.assertEqual(_sign(bytes.fromhex(secret), bytes.fromhex(message)).hex(), signature)

    def test_rejects_altered_message_signature_or_key(self):
        _, public, message, signature = RFC8032[2]
        public, message, signature = bytes.fromhex(public), bytes.fromhex(message), bytes.fromhex(signature)
        self.assertFalse(sig.ed25519_verify(public, message + b"\x00", signature))
        self.assertFalse(sig.ed25519_verify(public, message, signature[:-1] + b"\x0b"))
        self.assertFalse(sig.ed25519_verify(bytes.fromhex(RFC8032[1][1]), message, signature))

    def test_rejects_malleable_s(self):
        # s + L verifies under the bare group equation; RFC 8032 requires rejecting s >= L.
        _, public, message, signature = (bytes.fromhex(v) for v in RFC8032[1])
        s = int.from_bytes(signature[32:], "little") + sig._L
        self.assertFalse(sig.ed25519_verify(public, message, signature[:32] + s.to_bytes(32, "little")))

    def test_rejects_bad_lengths_and_non_canonical_points(self):
        _, public, message, signature = (bytes.fromhex(v) for v in RFC8032[1])
        self.assertFalse(sig.ed25519_verify(public[:31], message, signature))
        self.assertFalse(sig.ed25519_verify(public, message, signature[:63]))
        # y = p is the non-canonical encoding of y = 0.
        non_canonical = (2 ** 255 - 19).to_bytes(32, "little")
        self.assertFalse(sig.ed25519_verify(non_canonical, message, signature))
        self.assertFalse(sig.ed25519_verify(public, message, non_canonical + signature[32:]))


def fixture_keys():
    with open(os.path.join(FIXTURES, "infrastructure_agent_jwks.json"), "rb") as f:
        return sig.parse_keys(f.read(), "fixture")


class ParseKeysTest(unittest.TestCase):
    def test_parses_published_jwks(self):
        keys = fixture_keys()
        self.assertEqual([kid for kid, _ in keys], ["NRInfraAgent/0"])
        self.assertEqual(len(keys[0][1]), 32)

    def test_keeps_every_published_version(self):
        # After a rotation the JWKS lists the new version first and keeps older ones.
        jwks = {"keys": [
            {"kty": "OKP", "crv": "Ed25519", "kid": "k/1", "x": base64.urlsafe_b64encode(_keypair(OTHER_SEED)[2]).decode().rstrip("=")},
            {"kty": "OKP", "crv": "Ed25519", "kid": "k/0", "x": base64.urlsafe_b64encode(TEST_KEY[1]).decode().rstrip("=")},
        ]}
        self.assertEqual([kid for kid, _ in sig.parse_keys(json.dumps(jwks).encode(), "test")], ["k/1", "k/0"])

    def test_skips_other_key_types_and_fails_when_none_left(self):
        jwks = {"keys": [{"kty": "EC", "crv": "P-256", "x": "AAAA", "y": "AAAA"}]}
        with self.assertRaisesRegex(sig.SignatureError, "no New Relic signing keys"):
            sig.parse_keys(json.dumps(jwks).encode(), "test")

    def test_rejects_non_json_and_oversized(self):
        with self.assertRaisesRegex(sig.SignatureError, "not a JSON key set"):
            sig.parse_keys(b"<html>", "test")
        with self.assertRaisesRegex(sig.SignatureError, "larger"):
            sig.parse_keys(b" " * (sig.MAX_JWKS_BYTES + 1), "test")


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


class FetchKeysTest(unittest.TestCase):
    URL = "https://publickeys.newrelic.com/g/agent-control-oci/global/test/jwks.json"

    def setUp(self):
        with open(os.path.join(FIXTURES, "infrastructure_agent_jwks.json"), "rb") as f:
            self.jwks = f.read()
        patcher = mock.patch.object(sig.time, "sleep")
        patcher.start()
        self.addCleanup(patcher.stop)

    def http_error(self, code):
        return sig.urllib.error.HTTPError(self.URL, code, "error", {}, io.BytesIO())

    def test_fetches_keys(self):
        with mock.patch.object(sig.urllib.request, "urlopen", return_value=FakeResponse(self.jwks)) as urlopen:
            self.assertEqual([kid for kid, _ in sig.fetch_keys(self.URL)], ["NRInfraAgent/0"])
        self.assertEqual(urlopen.call_args[0][0].full_url, self.URL)

    def test_retries_server_errors_and_timeouts(self):
        responses = [self.http_error(503), sig.socket.timeout("timed out"), FakeResponse(self.jwks)]
        with mock.patch.object(sig.urllib.request, "urlopen", side_effect=responses):
            self.assertEqual(len(sig.fetch_keys(self.URL)), 1)

    def test_missing_key_set_fails_without_retrying(self):
        with mock.patch.object(sig.urllib.request, "urlopen", side_effect=[self.http_error(404)]):
            with self.assertRaisesRegex(sig.SignatureError, "HTTP 404"):
                sig.fetch_keys(self.URL)

    def test_unreachable_after_retries(self):
        errors = [sig.urllib.error.URLError("no route")] * sig.KEYS_ATTEMPTS
        with mock.patch.object(sig.urllib.request, "urlopen", side_effect=errors):
            with self.assertRaisesRegex(sig.SignatureError, "could not reach"):
                sig.fetch_keys(self.URL)

    def test_requires_https(self):
        with self.assertRaisesRegex(sig.SignatureError, "HTTPS"):
            sig.fetch_keys("http://publickeys.newrelic.com/jwks.json")


class VerifyTest(unittest.TestCase):
    def test_real_oci_signer_signature(self):
        with open(os.path.join(FIXTURES, "infrastructure_agent_signature_manifest.json")) as f:
            manifest = json.load(f)
        keys = fixture_keys()
        registry = FakeRegistry(manifest=manifest)
        self.assertEqual(sig.verify(registry, REAL_DIGEST, REAL_REPOSITORY, keys), "NRInfraAgent/0")
        self.assertEqual(registry.requested, ["sha256-" + REAL_DIGEST.split(":")[1] + ".sig"])

    def test_real_signature_is_not_accepted_for_another_repository(self):
        with open(os.path.join(FIXTURES, "infrastructure_agent_signature_manifest.json")) as f:
            manifest = json.load(f)
        keys = fixture_keys()
        with self.assertRaisesRegex(sig.SignatureError, "infrastructure-agent-artifacts"):
            sig.verify(FakeRegistry(manifest=manifest), REAL_DIGEST, REPOSITORY, keys)

    def test_valid_signature(self):
        self.assertEqual(sig.verify(FakeRegistry([layer(payload())]), DIGEST, REPOSITORY, [TEST_KEY]), "test/0")

    def test_payload_in_blob(self):
        data = payload()
        entry = layer(data, inline=False)
        registry = FakeRegistry([entry], blobs={entry["digest"]: data})
        self.assertEqual(sig.verify(registry, DIGEST, REPOSITORY, [TEST_KEY]), "test/0")

    def test_missing_signature(self):
        with self.assertRaisesRegex(sig.SignatureError, "no signature found"):
            sig.verify(FakeRegistry(), DIGEST, REPOSITORY, [TEST_KEY])

    def test_signature_for_another_digest(self):
        other = "sha256:" + "cd" * 32
        with self.assertRaisesRegex(sig.SignatureError, "signature is for " + other):
            sig.verify(FakeRegistry([layer(payload(digest=other))]), DIGEST, REPOSITORY, [TEST_KEY])

    def test_signature_by_unknown_key(self):
        with self.assertRaisesRegex(sig.SignatureError, "does not verify"):
            sig.verify(FakeRegistry([layer(payload(), seed=OTHER_SEED)]), DIGEST, REPOSITORY, [TEST_KEY])

    def test_any_published_key_verifies(self):
        other_key = ("test/1", _keypair(OTHER_SEED)[2])
        registry = FakeRegistry([layer(payload(), seed=OTHER_SEED)])
        self.assertEqual(sig.verify(registry, DIGEST, REPOSITORY, [TEST_KEY, other_key]), "test/1")

    def test_tampered_inline_payload(self):
        entry = layer(payload())
        entry["data"] = base64.b64encode(payload(digest="sha256:" + "cd" * 32)).decode()
        with self.assertRaisesRegex(sig.SignatureError, "does not match"):
            sig.verify(FakeRegistry([entry]), DIGEST, REPOSITORY, [TEST_KEY])

    def test_payload_swapped_with_its_digest(self):
        # The attacker rewrites payload and digest together; only the signature can catch it.
        entry = layer(payload(), signature=_sign(TEST_SEED, payload(digest="sha256:" + "cd" * 32)))
        with self.assertRaisesRegex(sig.SignatureError, "does not verify"):
            sig.verify(FakeRegistry([entry]), DIGEST, REPOSITORY, [TEST_KEY])

    def test_wrong_payload_type(self):
        with self.assertRaisesRegex(sig.SignatureError, "type"):
            sig.verify(FakeRegistry([layer(payload(type_="something else"))]), DIGEST, REPOSITORY, [TEST_KEY])

    def test_any_valid_layer_is_enough(self):
        bad = layer(payload(), seed=OTHER_SEED)
        self.assertEqual(sig.verify(FakeRegistry([bad, layer(payload())]), DIGEST, REPOSITORY, [TEST_KEY]), "test/0")

    def test_no_layers(self):
        with self.assertRaisesRegex(sig.SignatureError, "no layers"):
            sig.verify(FakeRegistry([]), DIGEST, REPOSITORY, [TEST_KEY])

    def test_oversized_payload(self):
        entry = layer(payload())
        entry["size"] = sig.MAX_PAYLOAD_BYTES + 1
        with self.assertRaisesRegex(sig.SignatureError, "bytes"):
            sig.verify(FakeRegistry([entry]), DIGEST, REPOSITORY, [TEST_KEY])

    def test_identity_ignores_tag_and_registry_spelling(self):
        for reference in ("docker.io/newrelic/beyond-oci-metric-function:stable",
                          "index.docker.io/newrelic/beyond-oci-metric-function",
                          "newrelic/beyond-oci-metric-function:1.42"):
            registry = FakeRegistry([layer(payload(reference=reference))])
            self.assertEqual(sig.verify(registry, DIGEST, REPOSITORY, [TEST_KEY]), "test/0", reference)

    def test_identity_rejects_other_repository(self):
        for reference in ("docker.io/newrelic/oci-log-forwarder:1.0",
                          "docker.io/attacker/beyond-oci-metric-function:1.42",
                          "ghcr.io/newrelic/beyond-oci-metric-function:1.42"):
            with self.assertRaises(sig.SignatureError, msg=reference):
                sig.verify(FakeRegistry([layer(payload(reference=reference))]), DIGEST, REPOSITORY, [TEST_KEY])


class ResolveTest(unittest.TestCase):
    """resolve() checks the signature of the digest it returns, unless told not to."""

    def setUp(self):
        self.manifest = json.dumps({"schemaVersion": 2, "config": {}, "layers": []}).encode()
        self.digest = image_mirror.sha256_digest(self.manifest)
        patcher = mock.patch.object(image_mirror.Registry, "get_manifest",
                                    return_value=(image_mirror.OCI_MANIFEST, self.manifest))
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_verified_image_resolves(self):
        with mock.patch.object(sig, "fetch_keys", return_value=[TEST_KEY]), \
                mock.patch.object(sig, "verify", return_value="test/0") as verify:
            digest, tag = image_mirror.resolve("docker.io/newrelic/beyond-oci-metric-function:1.42", "linux/amd64")
        self.assertEqual((digest, tag), (self.digest, "1.42"))
        self.assertEqual(verify.call_args[0][1:3], (self.digest, image_mirror.SIGNED_REPOSITORY))

    def test_unsigned_image_fails(self):
        with mock.patch.object(sig, "fetch_keys", return_value=[TEST_KEY]), \
                mock.patch.object(sig, "verify", side_effect=sig.SignatureError("no signature found")):
            with self.assertRaisesRegex(image_mirror.RegistryError, "not signed by New Relic"):
                image_mirror.resolve("docker.io/newrelic/beyond-oci-metric-function:1.42", "linux/amd64")

    def test_unreachable_keys_fail_with_a_network_hint(self):
        with mock.patch.object(sig, "fetch_keys", side_effect=sig.SignatureError("could not reach it")):
            with self.assertRaisesRegex(image_mirror.RegistryError, "publickeys.newrelic.com"):
                image_mirror.resolve("docker.io/newrelic/beyond-oci-metric-function:1.42", "linux/amd64")

    def test_verification_can_be_turned_off(self):
        with mock.patch.object(sig, "fetch_keys") as fetch_keys, mock.patch.object(sig, "verify") as verify:
            image_mirror.resolve("docker.io/newrelic/beyond-oci-metric-function:1.42", "linux/amd64", False)
        fetch_keys.assert_not_called()
        verify.assert_not_called()

    def test_main_verifies_unless_query_says_false(self):
        for query, expected in (({}, True), ({"verify_signature": "true"}, True),
                                ({"verify_signature": "false"}, False)):
            query = dict(query, source_image="docker.io/newrelic/beyond-oci-metric-function:1.42")
            with mock.patch.object(image_mirror, "resolve", return_value=(self.digest, "1.42")) as resolve, \
                    mock.patch.object(sys, "argv", ["image_mirror.py", "resolve"]), \
                    mock.patch.object(sys, "stdin", io.StringIO(json.dumps(query))), \
                    mock.patch.object(sys, "stdout", io.StringIO()):
                image_mirror.main()
            self.assertIs(resolve.call_args[0][2], expected, query)


class SigningKeysUrlTest(unittest.TestCase):
    def test_url_is_https_and_lowercase(self):
        # publickeys.newrelic.com serves key names in lowercase only.
        self.assertTrue(image_mirror.SIGNING_KEYS_URL.startswith("https://publickeys.newrelic.com/g/"))
        self.assertEqual(image_mirror.SIGNING_KEYS_URL, image_mirror.SIGNING_KEYS_URL.lower())


if __name__ == "__main__":
    unittest.main()
