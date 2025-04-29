#!/bin/bash

# Parse command line arguments
site_id=""
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --site_id)
      site_id="$2"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      ;;
  esac
  shift
done

if [ -z "$site_id" ]; then
  echo "Error: You must provide a site id using --site_id"
  exit 1
fi

cd $WORKING_DIR
source $WORKING_DIR/volttron/env/bin/activate

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

# Check if Supabase is configured and enabled in the site config
SUPABASE_ENABLED=$(python3 -c "
import yaml
with open(f'site_configs/${site_id}.yaml', 'r') as f:
    config = yaml.safe_load(f)
print('true' if config['deployment_config']['enabled_services'].get('supabase', False) else 'false')
")

echo -e "\nList of Services"
echo "$SERVICES_STATUS" | grep -v "^---ENABLED---"

echo -e "\nInstalling Core services..."
sudo docker compose -f docker-compose.local.yml up --build -d
sudo docker compose -f docker-compose.local.yml stop


if [ "$SUPABASE_ENABLED" = "true" ]; then
    echo -e "\nInstalling Supabase services..."
    python $WORKING_DIR/scripts/installation_scripts_local/04_init-supabase-cred.py $WORKING_DIR/supabase/.env $site_id
    cd supabase
    sudo docker compose -f docker-compose.local.yml up -d
    cd $WORKING_DIR

    echo -e "\nInstalling CPMS services..."  # TODO: Make this optional and selectable
    cp .env $WORKING_DIR/alto-cero-interface/.env
    sudo docker compose -f docker-compose-cpms.local.yml up --build -d  # This include Django migrate command
    sudo docker compose -f docker-compose-cpms.local.yml stop

    # Enable Realtime for Supabase tables
    echo -e "\nEnabling Realtime for Supabase tables..."
    sudo docker exec -i supabase-db psql -U postgres -d postgres -c "
      ALTER PUBLICATION supabase_realtime ADD TABLE latest_data;
      ALTER PUBLICATION supabase_realtime ADD TABLE maintenance_history;
      ALTER PUBLICATION supabase_realtime ADD TABLE action_queue;
      ALTER PUBLICATION supabase_realtime ADD TABLE group_action_queue;
      ALTER PUBLICATION supabase_realtime ADD TABLE autopilot;
      ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
    "
fi