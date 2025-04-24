import logging
import os
import argparse
import yaml


WORKING_DIR = os.environ["WORKING_DIR"]
MODEL_SCHEMA_PATH = f"{WORKING_DIR}/model_schema.yaml"
MODEL_SCHEMA = yaml.safe_load(open(MODEL_SCHEMA_PATH, 'r'))


def validate_bacnet_agent_config(site_config: dict):
    """
    Validate the BACnet agent configuration. If the configuration file is not valid, raise an exception
    """
    REQUIRED_KEYS_AND_TYPES = [
        ('ip_address', str),
        ('interval', int),
        ('read_devices', dict),
    ]
    REQUIRED_DEVICE_KEYS_AND_TYPES = [
        ('model', str),
        ('servers', list),
    ]
    REQUIRED_SERVER_KEYS_AND_TYPES = [
        ('bacnet_ip', str),
        ('points', dict),
    ]
    
    agent_config = site_config["volttron_agents"]["bacnet"]

    # Validate top-level BACnet config
    for key, value_type in REQUIRED_KEYS_AND_TYPES:
        if key not in agent_config:
            raise ValueError(f"'{key}' is not defined in the BACnet agent configuration")
        elif not isinstance(agent_config[key], value_type):
            raise ValueError(f"'{key}' should be of type {value_type} in the BACnet agent configuration")
        
    # Validate the devices configuration
    bacnet_read_devices = agent_config["read_devices"]
    for dev_id, dev_info in bacnet_read_devices.items():
        # Check required device keys
        for key, value_type in REQUIRED_DEVICE_KEYS_AND_TYPES:
            if key not in dev_info:
                raise ValueError(f"[{dev_id}] '{key}' is not defined in the BACnet device configuration")
            elif not isinstance(dev_info[key], value_type):
                raise ValueError(f"[{dev_id}] '{key}' should be of type {value_type}")
        
        # Validate each server in the device
        for server_idx, server in enumerate(dev_info['servers']):
            for key, value_type in REQUIRED_SERVER_KEYS_AND_TYPES:
                if key not in server:
                    raise ValueError(f"[{dev_id}] Server {server_idx}: '{key}' is not defined")
                elif not isinstance(server[key], value_type):
                    raise ValueError(f"[{dev_id}] Server {server_idx}: '{key}' should be of type {value_type}")
            
    # Validate the BACnet device datapoint schema
    for dev_id, dev_info in bacnet_read_devices.items():
        dev_model = dev_info['model']
        
        if dev_model not in MODEL_SCHEMA:
            raise ValueError(f"Model '{dev_model}' for device '{dev_id}' is not in the model schema")

        schema_points = set(MODEL_SCHEMA[dev_model].keys())
        
        # Collect all points from all servers
        all_device_points = set()
        for server in dev_info['servers']:
            all_device_points.update(server['points'].keys())

        # Check points validity
        if not all_device_points.issubset(schema_points):
            diff_points = all_device_points - schema_points
            logging.error(f"These points {diff_points} for '{dev_id}' are not in the model schema")
            raise ValueError(f"These points {diff_points} for '{dev_id}' are not in the model schema")
        elif not schema_points.issubset(all_device_points):
            diff_points = schema_points - all_device_points
            logging.warning(f"These points {diff_points} for '{dev_id}' are not defined in the device config")
        else:
            logging.info(f"Verified device '{dev_id}' config successfully")



def validate_site_config(site_config: dict):
    """
    Validate the site configuration
    """
    SITE_METADATA_KEYS_AND_TYPES = [
        ('site_name', str),
        ('initial_date', str),
    ]

    REQUIRED_TOP_LEVEL_KEYS = [
        "site_id",
        "timezone",
        "deployment_config",
        "site_metadata",
        "volttron_agents"
    ]

    # Validate top-level keys
    for key in REQUIRED_TOP_LEVEL_KEYS:
        if key not in site_config:
            raise ValueError(f"'{key}' is not defined in the site config")

    # Validate site metadata
    for key, value_type in SITE_METADATA_KEYS_AND_TYPES:
        if key not in site_config["site_metadata"]:
            raise ValueError(f"'{key}' is not defined in the site metadata")
        elif not isinstance(site_config["site_metadata"][key], value_type):
            raise ValueError(f"'{key}' should be of type {value_type}")

    # Validate deployment config
    if not isinstance(site_config["deployment_config"].get("enabled_services"), dict):
        raise ValueError("'enabled_services' in deployment_config must be a dict")

    # Check dash_config only if alto-dash is enabled
    if "alto-dash" in site_config["deployment_config"].get("enabled_services", {}):
        if "dash_config" not in site_config:
            raise ValueError("'dash_config' is required when alto-dash service is enabled")

    # Only validate BACnet config if it exists in volttron_agents
    if site_config.get("volttron_agents", {}).get("bacnet"):
        validate_bacnet_agent_config(site_config)
    else:
        logging.info("No BACnet configuration found - skipping BACnet validation")


    print("Site config for site id: ", site_config["site_id"], " is valid!!!!!!!!")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("site_id", help="The id of the site to install agents for")
    args = parser.parse_args()

    site_config_path = f"{WORKING_DIR}/site_configs/{args.site_id}.yaml"

    # Load the site config
    site_config = yaml.safe_load(open(site_config_path, 'r'))
    assert "site_id" in site_config, "'site_id' is not defined in the site config"
    assert "site_metadata" in site_config, "'site_metadata' is not defined in the site config"
    
    validate_site_config(site_config)