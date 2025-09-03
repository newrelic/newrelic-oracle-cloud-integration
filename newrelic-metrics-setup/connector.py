import sys
import json
import requests
from typing import Dict, Any

# Read query from stdin
query = json.load(sys.stdin)
payloadUrl = query.get("payload_link")

def create_terraform_map(payload: Dict[str, Any]) -> Dict[str, str]:
    """
    Converts the payload into a Terraform-compatible map, handling regional connector hubs.
    """
    terraform_map = {}
    regions = payload.get("regions", [])

    for region_data in regions:
        region = region_data.get("region", "")
        connector_hubs = region_data.get("connector_hubs", [])
        hub_counter = 1
        for hub in connector_hubs:
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

            name = f"newrelic-metrics-connector-hub-{region}-{hub_counter}"
            terraform_map[name] = json.dumps({
                "name": name,
                "description": "[DO NOT DELETE] New Relic Metrics Connector Hub to distribute metrics to New Relic",
                "batch_size_in_kbs": 100,
                "batch_time_in_sec": 60,
                "region": region,
                "compartments": compartments
            })
            hub_counter += 1

    return terraform_map

def get_payload():
    try:
        response = requests.get(payloadUrl)
        response.raise_for_status()
        payload = response.json()
    except (requests.RequestException, ValueError) as e:
        # Return a properly formatted error that Terraform can handle
        print(json.dumps({
            "error": f"Error fetching or parsing payload: {e}",
            "ingest_key_ocid": "",
            "user_key_ocid": "",
            "terraform_map": "{}"
        }))
        return None

    ingest_key_ocid = payload.get("ingest_key_ocid", "")
    user_key_ocid = payload.get("user_key_ocid", "")
    terraform_map_result = create_terraform_map(payload)

    # Return the result with the exact keys expected by Terraform
    result = {
        "ingest_key_ocid": ingest_key_ocid,
        "user_key_ocid": user_key_ocid,
        "terraform_map": json.dumps(terraform_map_result)
    }
    print(json.dumps(result))
    return result

if __name__ == "__main__":
    get_payload()
