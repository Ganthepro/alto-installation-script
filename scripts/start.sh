#!/bin/bash

# This script starts the Alto CERO platform services and agents.
#
# Usage: ./start.sh [--ignore-bacnet-check]
#
# Arguments:
#   --ignore-bacnet-check: Skip validation of BACnet point configuration

WORKING_DIR="/home/gan/alto-cero-infra"
export WORKING_DIR=$WORKING_DIR

# Reading site_id from installed_site_id.txt
if [ ! -f "$WORKING_DIR/installed_site_id.txt" ]; then
    echo "Error: installed_site_id.txt not found in the directory."
    return 0 2>/dev/null || exit 0
else
    site_id=$(cat "$WORKING_DIR/installed_site_id.txt")
    export site_id=$site_id
fi

source $WORKING_DIR/volttron/env/bin/activate

# Read enabled services from site config
echo "Reading services from site config..."
SERVICES_STATUS=$(python3 -c "
import yaml
with open(f'site_configs/${site_id}.yaml', 'r') as f:
    config = yaml.safe_load(f)
enabled_services = []
all_services = []
for service, enabled in config['deployment_config']['enabled_services'].items():
    status = '✅' if enabled else '🛑'
    all_services.append(f'{status} {service.upper()}')
    if enabled:
        enabled_services.append(service)
print('\n'.join(all_services))
print('---ENABLED---')
print(' '.join(enabled_services))
") || {
    echo "Failed to get services from site config"
    return 1
}
echo "$SERVICES_STATUS"

if [[ ! "$*" =~ "--ignore-bacnet-check" ]]; then
    python $WORKING_DIR/scripts/config_check_scripts/check_exported_bacnet_points.py $site_id
    if [ $? -ne 0 ]; then
        >&2 echo "$0: There was an error checking the exported BACnet points. Aborting."
        return 0 2>/dev/null || return 1
    fi
else
    echo "Skipping BACnet points check..."
fi

echo "Starting Core services..."
docker compose -f $WORKING_DIR/docker-compose.yml up -d

# Check if Supabase is configured and enabled in the site config
SUPABASE_ENABLED=$(python3 -c "
import yaml
with open(f'site_configs/${site_id}.yaml', 'r') as f:
    config = yaml.safe_load(f)
print('true' if config['deployment_config']['enabled_services'].get('supabase', False) else 'false')
")
if [ "$SUPABASE_ENABLED" = "true" ]; then
    echo -e "\nStarting CPMS services..."  # TODO: Make this more general
    sudo docker compose -f docker-compose-cpms.yml up -d
fi

echo "Warming up the services..."
sleep 10

vctl start --all-tagged

echo "Alto CERO: Platform initialization complete."