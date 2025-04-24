# -------------------------------------------------------------------------
# Reference: https://github.com/Azure/azure-iot-sdk-python/blob/main/samples/sync-samples/provision_symmetric_key.py
# Reference: https://learn.microsoft.com/en-us/azure/iot-dps/how-to-legacy-device-symm-key?tabs=linux&pivots=programming-language-python
# Reference: https://learn.microsoft.com/en-us/python/api/azure-iot-hub/azure.iot.hub.iothubregistrymanager?view=azure-python#azure-iot-hub-iothubregistrymanager-update-twin
# --------------------------------------------------------------------------

from azure.iot.device import ProvisioningDeviceClient
from azure.iot.hub import IoTHubRegistryManager
from azure.iot.hub.protocol.models import Twin
import os
import base64
import hmac
import hashlib
from dotenv import load_dotenv
import argparse
import yaml

load_dotenv()

messages_to_send = 10
provisioning_host = os.getenv("PROVISIONING_HOST")
id_scope = os.getenv("PROVISIONING_IDSCOPE")
registration_id = os.getenv("DEVICE_ID")
WORKING_DIR = os.environ["WORKING_DIR"]


def get_symmetric_key():
    group_primary_key = os.getenv("PROVISIONING_GROUP_PRIMARY_KEY")

    # Decode base64 key
    key_bytes = base64.b64decode(group_primary_key)

    # Create HMAC-SHA256 hash of registration ID using decoded key
    message = registration_id.encode("utf-8")
    signing_key = hmac.new(key_bytes, message, hashlib.sha256)

    # Encode final key in base64
    symmetric_key = base64.b64encode(signing_key.digest()).decode("utf-8")

    return symmetric_key


symmetric_key = get_symmetric_key()


def main():
    parser = argparse.ArgumentParser(
        description='Provision IoT Edge symmetric key.')
    parser.add_argument('site_id', type=str,
                        help='Name of the site configuration to use.')
    args = parser.parse_args()
    SITE_ID = args.site_id
    SITE_CONFIG_PATH = f"{WORKING_DIR}/site_configs/{SITE_ID}.yaml"
    site_config = yaml.safe_load(open(SITE_CONFIG_PATH, 'r'))

    provisioning_device_client = ProvisioningDeviceClient.create_from_symmetric_key(
        provisioning_host=provisioning_host,
        registration_id=registration_id,
        id_scope=id_scope,
        symmetric_key=symmetric_key,
    )

    registration_result = provisioning_device_client.register()

    print("The complete iot edge registration result is")
    print(registration_result.registration_state)

    device_connection_string = f"HostName={os.getenv('IOT_HUB_NAME')}.azure-devices.net;DeviceId={registration_id};SharedAccessKey={symmetric_key}"
    try:
        # replace the iothub connection string in the site config with the new one
        site_config["volttron_agents"]["iothub"]["connection_string"] = device_connection_string
        with open(SITE_CONFIG_PATH, 'w') as f:
            yaml.dump(site_config, f)
    except Exception as e:
        print(f"Error updating site config: {e}")

    # read the env file and append the device connection string if it doesn't exist
    # if it does exist, update the device connection string
    with open(os.path.join(os.getenv("WORKING_DIR"), ".env"), "r") as f:
        lines = f.readlines()

    for i, line in enumerate(lines):
        if not line.endswith("\n"):
            lines[i] = f"{line}\n"

    # Find and replace or append the connection string
    for i, line in enumerate(lines):
        if line.strip().startswith("IOT_HUB_DEVICE_CONNECTION_STRING"):
            lines[i] = f'IOT_HUB_DEVICE_CONNECTION_STRING="{device_connection_string}"\n'
            break
    else:
        lines.append(f'IOT_HUB_DEVICE_CONNECTION_STRING="{device_connection_string}"\n')

    # Write back all lines to the file
    with open(os.path.join(os.getenv("WORKING_DIR"), ".env"), "w") as f:
        f.writelines(lines)

    # update the device twin
    load_dotenv()  # load the env file again since it was modified
    iothub_registry_manager = IoTHubRegistryManager.from_connection_string(
        os.getenv("IOT_HUB_CONNECTION_STRING")
    )
    twin = iothub_registry_manager.get_twin(registration_id)
    twin_patch = Twin(
        tags={
            "site_id": SITE_ID,
            "environment": os.getenv("ENVIRONMENT"),
            "device_type": os.getenv("DEVICE_TYPE"),
        }
    )
    twin = iothub_registry_manager.update_twin(
        registration_id, twin_patch, twin.etag)


if __name__ == "__main__":
    main()