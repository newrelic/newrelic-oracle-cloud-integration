import io
import json
import logging
import os
import gzip
import base64
import time

from fdk import context, response
import requests
from requests.adapters import HTTPAdapter
from requests.exceptions import HTTPError

import oci
from oci.secrets.secrets_client import SecretsClient
import oci.auth.signers

# Initialize logger
logger = logging.getLogger(__name__)

# Output message version
OUTPUT_MESSAGE_VERSION = "v1.0"
# Determine if detailed logging is enabled based on environment variable
detailed_logging_enabled = eval(os.environ.get("LOGGING_ENABLED"))
# New Relic metric endpoint
nr_metric_endpoint = os.getenv('NR_METRIC_ENDPOINT')
# Tenancy OCID
tenancy_ocid = os.environ.get("TENANCY_OCID")
# Flag to forward metrics to New Relic
forward_to_nr = eval(os.getenv('FORWARD_TO_NR'))
# Function build version based on current datetime
function_build_version = os.getenv("FUNCTION_BUILD_VERSION", "1.0")
# OCI Vault related configurations
vaul_region = os.getenv("VAULT_REGION")
sec_ocid = os.getenv("SECRET_OCID")

# Max pool size for HTTP adapter
_max_pool = int(os.environ.get("NR_MAX_POOL", 10))
# Create a session
_session = requests.Session()
# Mount the HTTP adapter to the session for better connection pooling
_session.mount("https://", HTTPAdapter(pool_connections=_max_pool))

def fetch_api_key_from_vault(secret_ocid, vault_region) -> str:
    try:
        # Create a resource principal authentication provider
        rp = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()

        # Create a SecretsClient using the RP provider
        secrets_client = oci.secrets.SecretsClient(config={}, signer=rp)
        secrets_client.base_client.set_region(vault_region)

        # Set retry policy
        retry_strategy = oci.retry.DEFAULT_RETRY_STRATEGY
        secrets_client.base_client.retry_strategy = retry_strategy

        # Fetch the secret
        sc_response = secrets_client.get_secret_bundle(secret_id=secret_ocid)

        # Extract and decode the secret
        secret_content = sc_response.data.secret_bundle_content
        if not isinstance(secret_content, oci.secrets.models.Base64SecretBundleContentDetails) or secret_content.content is None:
            raise ValueError("Secret content is nil")

        decoded_secret = base64.b64decode(secret_content.content).decode('utf-8')
        return decoded_secret

    except Exception as e:
        logging.error(f"Failed to fetch API key from vault: {e}")
        raise RuntimeError(f"Failed to fetch API key from vault: {e}")

def _generate_metrics_msg(
        ctx: context.InvokeContext,
        serialized_metric_data,
) :
    """
    Generates a metrics message.
    :param ctx: Invoke context
    :param serialized_metric_data: Serialized metric data
    :return: Metrics message as a JSON string
    """
    if not tenancy_ocid:
        raise ValueError("Missing environment variable: TENANCY_OCID")

    # Bump OUTPUT_MESSAGE_VERSION any time this
    # structure gets updated
    message_dict = {
        "version": OUTPUT_MESSAGE_VERSION,
        "payload": {
            "headers": {
                "tenancy_ocid": tenancy_ocid,
                "source_fn_app_ocid": ctx.AppID(),
                "source_fn_app_name": ctx.AppName(),
                "source_fn_ocid": ctx.FnID(),
                "source_fn_name": ctx.FnName(),
                "source_fn_call_id": ctx.CallID(),
                "function_version": function_build_version
            },
            "body": json.loads(serialized_metric_data),
        },
    }

    if detailed_logging_enabled:
        logger.debug(f"Generated metrics message : {message_dict}")

    return json.dumps(message_dict)

def gzip_json(json_str):
    """
    Compresses a JSON string using gzip.
    :param json_str: JSON string to compress
    :return: Compressed data in bytes
    """
    # Encode the JSON string into bytes, gzip requires bytes
    json_bytes = json_str.encode()

    # Compress the bytes
    compressed_data = gzip.compress(json_bytes)

    return compressed_data


def _send_metrics_msg_to_newrelic(metrics_message) :
    """
    Sends metrics message to New Relic..
    :param metrics_message: Metrics message as a string
    :return: HTTP response text
    """
    #nr_ingest_key_vault = fetch_api_key_from_vault(sec_ocid, vaul_region)
    nr_ingest_key = os.getenv("NR_INGEST_KEY")

    if not nr_metric_endpoint or not nr_ingest_key:
        raise ValueError("Missing environment variables: NR_METRIC_ENDPOINT or NR_INGEST_KEY")

    if detailed_logging_enabled:
        logger.debug(f"Preparing to send metrics message to New Relic decode: {metrics_message}")

    # Compress the metrics message using gzip.
    compressed_payload = gzip_json(metrics_message)

    if detailed_logging_enabled:
        logger.debug(f"Compressed payload size: {len(compressed_payload)} bytes")

    api_headers = {
        "content-type": "application/json",
        'X-License-Key': nr_ingest_key
    }

    if forward_to_nr is False:
        if detailed_logging_enabled:
            logging.getLogger().debug("Metric Reporting is disabled - nothing sent")
        return ""

    if detailed_logging_enabled:
        logger.debug(f"Sending metrics to New Relic endpoint: {nr_metric_endpoint} with headers: {api_headers} with gzip payload: {compressed_payload}")

    http_response = _session.post(nr_metric_endpoint, data=compressed_payload, headers=api_headers)
    http_response.raise_for_status()

    if detailed_logging_enabled:
        logger.debug(f"Sent payload size={len(compressed_payload)} encoding={api_headers.get('content-encoding', None)}")
    return http_response.text


def handler(ctx: context.InvokeContext, data: io.BytesIO = None) -> response.Response:
    """
    Handler function for the function.
    :param ctx: Invoke context
    :param data: Input data
    :return: Response
    """
    if detailed_logging_enabled:
        logger.debug("Handler function started")

    try:
        # Get raw data from input
        raw_data = data.getvalue().decode("utf-8")
        if detailed_logging_enabled:
            logger.debug("Raw Data: " + raw_data)

        # Process the formatted data (e.g., send to New Relic)
        metrics_message = _generate_metrics_msg(ctx, raw_data)

        result = _send_metrics_msg_to_newrelic(metrics_message)

    except HTTPError as e:
        logger.exception("Error sending metrics to New Relic")
        result = e.response.text
    except Exception as e:
        logger.exception("Unexpected error while processing input data")
        result = str(e)

    if detailed_logging_enabled:
        logger.debug("Handler function finished")

    return response.Response(
        ctx,
        response_data=json.dumps({"result": result}),
        headers={"Content-Type": "application/json"},
    )
