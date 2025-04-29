#!/bin/bash
WORKING_DIR="/home/gan/alto-installation-script"
export WORKING_DIR=$WORKING_DIR

# Terminal colors and styles
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'

# Select installation type
echo -e "${BLUE}Select installation type:${NC}"
echo -e "${GREEN}1. Local installation${NC}"
echo -e "${GREEN}2. OTA installation${NC}"
read -p "Enter the number of your choice: " INSTALL_TYPE

if [ "$INSTALL_TYPE" == "1" ]; then
    read -p "Enter the site_id: " site_id
    if [ -z "$site_id" ]; then
        echo -e "${RED}Site ID is required. Exiting.${NC}"
        exit 1
    fi
    read -p "Enter the with_azure (true/false): " with_azure
    if [ "$with_azure" == "true" ]; then
        bash $WORKING_DIR/scripts/install-local.sh --site_id $site_id --with_azure
    else
        bash $WORKING_DIR/scripts/install-local.sh --site_id $site_id
    fi
elif [ "$INSTALL_TYPE" == "2" ]; then
    read -p "Enter the Token: " token
    if [ -z "$token" ]; then
        echo -e "${RED}Token is required. Exiting.${NC}"
        exit 1
    fi
    bash $WORKING_DIR/scripts/install-ota.sh --token $token
else
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
fi
