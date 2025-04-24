import argparse
import logging

import BAC0
import pandas as pd
import yaml
import os

BACNET_DEVICE = 24
WORKING_DIR = os.environ["WORKING_DIR"]


def check_config_and_scanned_points(read_devices_config: dict, write_devices_config: dict, scanned_df: pd.DataFrame):
    """
    Validate the configuration of the BACnet agent and the actual points exported from the BACnet device.
    """
    error_count = 0
    scanned_dev_ids = set(scanned_df['device_id'].unique())
    
    config_dev_ids = set(read_devices_config.keys()) | set(write_devices_config.keys())

    if scanned_dev_ids - config_dev_ids:
        logging.warning(f"Scanned devices not in YAML config: {scanned_dev_ids - config_dev_ids}")
    if config_dev_ids - scanned_dev_ids:
        error_count += 1
        logging.error(f"Configured devices not in scanned BACnet device: {config_dev_ids - scanned_dev_ids}")
    
    # Check read devices
    for dev_id, dev_info in read_devices_config.items():
        for server in dev_info['servers']:
            points = server['points']
            scanned_df_each_dev = scanned_df[scanned_df['device_id'] == dev_id]

            for p_name, p_address in points.items():
                p_data = scanned_df_each_dev[scanned_df_each_dev['datapoint'] == p_name]

                if p_data.empty:
                    error_count += 1
                    logging.error(f" [{dev_id}] Point {p_name} not found in scanned points")
                elif len(p_data) > 1:
                    error_count += 1
                    logging.error(f" [{dev_id}] Point {p_name} has multiple addresses in scanned points")
                else:
                    scanned_p_address = p_data['point_address'].item()
                    if p_address != scanned_p_address:
                        error_count += 1
                        logging.error(f" [{dev_id}] Point {p_name} address in BACnet device ({scanned_p_address}) is different from the configuration ({p_address})")

    # Check write devices  
    for dev_id, dev_info in write_devices_config.items():
        for server in dev_info['servers']:
            points = server['points']
            scanned_df_each_dev = scanned_df[scanned_df['device_id'] == dev_id]

            for p_name, p_address in points.items():
                p_data = scanned_df_each_dev[scanned_df_each_dev['datapoint'] == p_name]

                if p_data.empty:
                    error_count += 1
                    logging.error(f" [{dev_id}] Point {p_name} not found in scanned points")
                elif len(p_data) > 1:
                    error_count += 1
                    logging.error(f" [{dev_id}] Point {p_name} has multiple addresses in scanned points")
                else:
                    scanned_p_address = p_data['point_address'].item()
                    if p_address != scanned_p_address:
                        error_count += 1
                        logging.error(f" [{dev_id}] Point {p_name} address in BACnet device ({scanned_p_address}) is different from the configuration ({p_address})")
    
    if error_count:
        raise ValueError(f"Found {error_count} errors in the BACnet configuration and scanned points. Please solve them before proceeding.")
    else:
        print("BACnet configuration and scanned points are consistent!!!")


if __name__ == '__main__':

    # Set up argparse to accept the site_id argument
    parser = argparse.ArgumentParser(description='Install Volttron agents with specified configuration.')
    parser.add_argument('site_id', type=str, help='Id of the site configuration to use.')

    # Parse the arguments and load config file
    args = parser.parse_args()
    SITE_ID = args.site_id
    if SITE_ID.endswith('.yaml'):
        SITE_ID = SITE_ID[:-5]
    bacnet_config_path = f'{WORKING_DIR}/site_configs/{SITE_ID}.yaml'
    bacnet_agent_config = yaml.safe_load(open(bacnet_config_path))['volttron_agents']['bacnet']
    read_devices_config = bacnet_agent_config['read_devices']
    write_devices_config = bacnet_agent_config['write_devices']
    host_ip_address = bacnet_agent_config['ip_address']

    # Get unique server IPs from both read and write devices
    server_ips = set()
    for devices in [read_devices_config.values(), write_devices_config.values()]:
        for dev in devices:
            for server in dev['servers']:
                server_ips.add(server['bacnet_ip'])

    # Initialize BAC0 client
    client = BAC0.lite(ip=host_ip_address, port=0xBAC0)
    
    # Get and preprocess points dataframe from all BACnet devices
    all_dfs = []
    for server_ip in server_ips:
        bacnet_dev = BAC0.device(server_ip, BACNET_DEVICE, client)
        if isinstance(bacnet_dev, BAC0.core.devices.Device.DeviceDisconnected):
            raise ValueError(f"Failed to connect to BACnet device at {server_ip}")
            
        df = bacnet_dev.points_properties_df()
        df = df.transpose()
        df['device_id'] = df['name'].apply(lambda x: x.split('.')[-2])
        df['datapoint'] = df['name'].apply(lambda x: x.split('.')[-1])
        df['point_address'] = df.apply(lambda row: f"{row['type']} {row['address']}", axis=1)
        df = df[['device_id', 'datapoint', 'point_address']]
        all_dfs.append(df)
    
    # Concatenate all dataframes
    df = pd.concat(all_dfs, ignore_index=True)
    
    # Check configuration and scanned points
    check_config_and_scanned_points(read_devices_config, write_devices_config, df)
