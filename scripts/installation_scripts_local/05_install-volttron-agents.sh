#!/bin/bash

# VOLTTRON Agents Installer
#
# This script is a wrapper that calls the main install_agents.py script from alto_os.
# It handles activating the virtual environment and passing the correct site config directory.
#
# Usage:
#   ./05_install-volttron-agents.sh <site_id>

set -e

# Check if site_id is provided
if [ "$#" -ne 1 ]; then
    echo "Error: Missing site ID argument."
    echo "Usage: $0 <site_id>"
    exit 1
fi

SITE_ID="$1"

# Check if WORKING_DIR is set
if [ -z "$WORKING_DIR" ]; then
    echo "Error: WORKING_DIR environment variable not set."
    exit 1
fi

# Verify site config exists
SITE_CONFIG_PATH="${WORKING_DIR}/site_configs/${SITE_ID}.yaml"
if [ ! -f "$SITE_CONFIG_PATH" ]; then
    echo "Error: Site config file not found at $SITE_CONFIG_PATH"
    exit 1
fi

# Path to the install_agents.py script
INSTALL_SCRIPT_PATH="${WORKING_DIR}/alto_os/scripts/install_agents.py"
if [ ! -f "$INSTALL_SCRIPT_PATH" ]; then
    echo "Error: install_agents.py script not found at $INSTALL_SCRIPT_PATH"
    exit 1
fi

# Activate the virtual environment and run the install_agents.py script
echo "Installing VOLTTRON agents with config: $SITE_CONFIG_PATH"

# Activate the VOLTTRON environment
source "${WORKING_DIR}/volttron/env/bin/activate"

# Run the install_agents.py script
python "$INSTALL_SCRIPT_PATH" "$SITE_ID" --site_config_dir "${WORKING_DIR}/site_configs"

# Check if the installation was successful
if [ $? -eq 0 ]; then
    echo "✅ Successfully installed VOLTTRON agents."
else
    echo "Error: Failed to install VOLTTRON agents."
    exit 1
fi
