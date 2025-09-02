import sys
import json
import requests
from typing import Dict, Any

# Read query from stdin
query = json.load(sys.stdin)
payloadUrl = query.get("payload_link")

def create_terraform_map(payload: Dict[str, Any]) -> Dict[str, str]:
    """
    Converts the payload into a Terraform-compatible map, skipping hubs with empty compartments.
    """
    terraform_map = {}
    connector_hubs = payload.get("connector_hubs", [])
    for idx, hub in enumerate(connector_hubs, start=1):
        compartments = [
            {
                "compartment_id": comp.get("compartment_id"),
                "namespaces": comp.get("namespaces", [])
            }
            for comp in hub.get("compartments", [])
        ]
        if not compartments:
            # Skip this hub if compartments is empty
            continue
        name = f"newrelic-metrics-connector-hub-{idx}"
        terraform_map[name] = json.dumps({
            "name": name,
            "description": "[DO NOT DELETE] New Relic Metrics Connector Hub to distribute metrics to New Relic",
            "batch_size_in_kbs": 100,
            "batch_time_in_sec": 60,
            "compartments": compartments
        })
    return terraform_map

def get_payload():
    try:
        response = requests.get(payloadUrl)
        response.raise_for_status()
        payload = response.json()
    except (requests.RequestException, ValueError) as e:
        print(json.dumps({"error": f"Error fetching or parsing payload: {e}"}))
        return

    ingest_key_ocid = payload.get("ingest_key_ocid", "")
    user_key_ocid = payload.get("user_key_ocid", "")
    terraform_map_result = create_terraform_map(payload)
    # Convert terraform_map to a JSON string so all output values are strings.
    result = {
        "ingest_key_ocid": ingest_key_ocid,
        "user_key_ocid": user_key_ocid,
        "terraform_map": json.dumps(terraform_map_result)
    }
    print(json.dumps(result))

if __name__ == "__main__":
    get_payload()
