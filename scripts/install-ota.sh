#!/bin/bash

# This script installs and configures the Alto CERO Chiller infrastructure for a specified site.
# It handles installation, setting up necessary dependencies, configuring services,
# and installing required applications.
#
# Usage: ./install.sh --token <token>
#
# Arguments:
#   --token: The token to use for the installation.
#
# Note: Before running this script, make sure to run init-submodules.sh first
# to initialize and update all required git submodules.

# Initialize variables
site_id=""
token=""
with_azure=true


# Terminal colors and styles
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Progress tracking variables
total_steps=0
current_step=0
LOG_FILE="/tmp/alto_install_$$.log"
touch "$LOG_FILE"


# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
    --token)
        token="$2"
        shift
        ;;
    *)
        echo "Unknown option: $1"
        ;;
    esac
    shift
done

echo "Installing git submodules..."
git submodule update --init alto-cero-automation-backend

echo "Installing jq..."
sudo apt install -y jq 2>&1 | tee -a "$LOG_FILE"

URL="https://iot-api.edusaig.com/api/device/env"

if ! command -v jq &>/dev/null; then
    echo "Error: jq is not installed. Please install jq to proceed."
    exit 1
fi

# Make the request and capture response and status code
HTTP_RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" -H "Authorization: Bearer $token" "$URL")

# Extract body and status code
BODY=$(echo "$HTTP_RESPONSE" | sed -e 's/HTTPSTATUS\:.*//g')
STATUS_CODE=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

# Check HTTP status code
if [ "$STATUS_CODE" -ne 200 ]; then
    echo "❌ Request failed with status code $STATUS_CODE"
    echo "Response: $BODY"
    exit 1
fi

# Save to .env file
echo "✅ Request successful. Saving to .env..."
jq -r 'to_entries[] | "\(.key | ascii_upcase)=\(.value)"' <<<"$BODY" >.env

echo ".env file created:"
cat .env
export $(cat .env | xargs)
site_id=$(echo $SITE_ID | tr -d '"')

# Download site config
if [ ! -f "$WORKING_DIR/site_configs/$site_id.yaml" ]; then
    echo "Site config does not exist, creating it"
    mkdir -p "$WORKING_DIR/site_configs"  # Ensure the directory exists
else
    echo "Site config already exists, replacing it"
    rm -f "$WORKING_DIR/site_configs/$site_id.yaml"
fi

http_status=$(curl -s -w "%{http_code}" -o "$WORKING_DIR/site_configs/$site_id.yaml" \
    -H "Authorization: Bearer $token" \
    "https://iot-api.edusaig.com/api/config/me")

if [ "$http_status" -eq 200 ]; then
    echo "✅ Site config downloaded"
else
    echo "❌ Site config download failed with status: $http_status"
    rm -f "$WORKING_DIR/site_configs/$site_id.yaml"  # Remove partial file if needed
    exit 1  
fi
http_status=$(curl -s -w "%{http_code}" -o "$WORKING_DIR/site_configs/$site_id.yaml" \
    -H "Authorization: Bearer $token" \
    "https://iot-api.edusaig.com/api/config/me")

if [ "$http_status" -eq 200 ]; then
    echo "✅ Site config downloaded"
else
    echo "❌ Site config download failed with status: $http_status"
    exit 1
fi


# Installation scripts
INSTALL_SCRIPTS=(
    "sudo bash $WORKING_DIR/scripts/installation_scripts/01_install-docker.sh"
    "sudo docker image prune -f"
)

# Function to show progress and tail logs simultaneously
show_progress_and_logs() {
    local step_name="$1"
    current_step=$((current_step + 1))
    local percentage=$((current_step * 100 / total_steps))
    local filled=$((percentage / 2))
    local empty=$((50 - filled))

    # Create the progress bar
    local progress_bar="["
    for ((i = 0; i < filled; i++)); do
        progress_bar+="#"
    done
    for ((i = 0; i < empty; i++)); do
        progress_bar+=" "
    done
    progress_bar+="]"

    # Print progress with fixed width
    printf "\n${BLUE}[%d/%d]${NC} %s %d%% - %s\n" "$current_step" "$total_steps" "$progress_bar" "$percentage" "$step_name"

    # Show the log file but only the last 5 lines
    echo -e "${YELLOW}--- Last logs ---${NC}"
    tail -n 5 "$LOG_FILE"
    echo -e "${YELLOW}---------------${NC}"
}

# Function to print status updates
print_status() {
    local message="$1"
    local status="$2" # success, error, info, or warning
    local prefix=""

    case "$status" in
    success)
        prefix="${GREEN}[✓]${NC}"
        ;;
    error)
        prefix="${RED}[✗]${NC}"
        ;;
    info)
        prefix="${BLUE}[i]${NC}"
        ;;
    warning)
        prefix="${YELLOW}[!]${NC}"
        ;;
    *)
        prefix="${BLUE}[i]${NC}"
        ;;
    esac

    echo -e "$prefix $message"
    echo "[$(date)] $status: $message" >>"$LOG_FILE"
}

# Install dependencies
install_dependencies() {
    show_progress_and_logs "Installing required dependencies"

    print_status "Installing python3..." "info"
    #sudo apt install -y python3 2>&1 | tee -a "$LOG_FILE"
    sudo apt install -y python3 python3-pip 2>&1 | tee -a "$LOG_FILE"

    print_status "Installing required Python packages..." "info"
    pip3 install google-auth==2.28.1 google-auth-oauthlib==1.2.0 google-api-python-client==2.119.0 2>&1 | tee -a "$LOG_FILE"
    pip3 install azure-iot-device==2.6.0 azure-iot-hub==2.6.1 python-dotenv==1.0.1 2>&1 | tee -a "$LOG_FILE"

    # Validate site configuration
    # print_status "Validating site configuration for '$site_id'..." "info"
    # if ! python3 $WORKING_DIR/scripts/config_check_scripts/check_site_config.py $site_id 2>&1 | tee -a "$LOG_FILE"; then
    #   print_status "The site config for '$site_id' file is incorrectly formatted. Please fix the errors and try again." "error"
    #   return 1
    # fi

    print_status "Site config for '$site_id' is valid." "success"
    return 0
}

# Execute installation scripts
run_installation_scripts() {
    local scripts=("$@")
    local script_name=""

    for script in "${scripts[@]}"; do
        # Extract a readable name from the script path
        if [[ $script == *"bash"* ]]; then
            script_name=$(echo "$script" | grep -o '[0-9]\{2\}_[a-zA-Z0-9_-]\+\.sh' || echo "$script")
        else
            script_name="$script"
        fi

        show_progress_and_logs "Executing $script_name"
        print_status "Running: $script" "info"

        # Run the command and tee output to the log file
        eval $script 2>&1 | tee -a "$LOG_FILE"
        local exit_code=${PIPESTATUS[0]}

        if [ $exit_code -ne 0 ]; then
            print_status "Error executing '$script_name'." "error"
            return 1
        else
            print_status "Successfully completed '$script_name'." "success"
        fi
    done

    return 0
}

# Main execution flow
main() {
    if [ -z "$site_id" ]; then
        print_status "You must provide a site id using --site_id." "error"
        return 1
    fi

    if [ ! -e "$WORKING_DIR/site_configs/$site_id.yaml" ]; then
        print_status "Site config file for '$site_id' does not exist." "error"
        return 1
    fi

    if [ ! -f "$WORKING_DIR/.env" ]; then
        print_status ".env file does not exist in $WORKING_DIR. Installation cancelled." "error"
        return 1
    fi

    # Calculate total steps (dependencies + number of scripts)
    total_steps=$((1 + ${#INSTALL_SCRIPTS[@]}))

    if $with_azure; then
        # Add Azure-specific scripts to the total count
        total_steps=$((total_steps + 5))
    fi

    # Clear screen and start fresh
    
    clear

    echo -e "${BOLD}${GREEN}
     █████╗ ██╗  ████████╗ ██████╗      ██████╗ ███████╗
    ██╔══██╗██║  ╚══██╔══╝██╔═══██╗    ██╔═══██╗██╔════╝
    ███████║██║     ██║   ██║   ██║    ██║   ██║███████╗
    ██╔══██║██║     ██║   ██║   ██║    ██║   ██║╚════██║
    ██║  ██║███████╗██║   ╚██████╔╝    ╚██████╔╝███████║
    ╚═╝  ╚═╝╚══════╝╚═╝    ╚═════╝      ╚═════╝ ╚══════╝${NC}"

    echo -e "\n${BOLD}Installing Alto OS 2.0 with id: ${BLUE}$site_id${NC}${BOLD}${NC}"
    echo -e "${BOLD}${YELLOW}Progress: [0/${total_steps}] Starting installation...${NC}\n"
    echo -e "${YELLOW}Log file: ${LOG_FILE}${NC}"

    if ! install_dependencies; then
        return 1
    fi

    if $with_azure; then
        INSTALL_SCRIPTS+=(
            "eval $(cat $WORKING_DIR/.env | sed 's/^/export /')"
            "python3 $WORKING_DIR/scripts/installation_scripts/03_provision_iot_edge_symmetric_key.py $site_id"
            "eval $(cat $WORKING_DIR/.env | sed 's/^/export /')"
            "chmod +x $WORKING_DIR/scripts/installation_scripts/04_install-azure-iot-edge.sh"
            "bash $WORKING_DIR/scripts/installation_scripts/04_install-azure-iot-edge.sh"
            "sudo apt install lm-sensors"
            "bash $WORKING_DIR/scripts/installation_scripts/05_install-core.sh --site_id $site_id --token $token"
        )
    fi

    if ! run_installation_scripts "${INSTALL_SCRIPTS[@]}"; then
        print_status "Installation failed." "error"
        return 1
    fi

    # Record successful installation
    print_status "Alto CERO: Installation complete. Your system is ready!" "success"
    echo "$site_id" >"$WORKING_DIR/installed_site_id.txt"

    URL="https://iot-api.edusaig.com/api/device/"

    response=$(curl -s -w "%{http_code}" -o response.json \
        -X PATCH "$URL" \
        -H "Content-Type: application/json" \
        -H 'accept: */*' \
        -H "Authorization: Bearer $token" \
        --data '{
            "is_setup": true
        }')

    if [ "$response" -eq 204 ]; then
        echo "✅ Request successful (204). No content returned."
    else
        echo "❌ Request failed with HTTP code $response"
        cat response.json
        exit 1
    fi

    echo -e "\n${GREEN}${BOLD}----------------------------------------${NC}"
    echo -e "${GREEN}${BOLD}Installation completed successfully!${NC}"
    echo -e "${GREEN}${BOLD}----------------------------------------${NC}"
    echo -e "${YELLOW}Full installation log saved to: ${LOG_FILE}${NC}\n"
}

main "$@"
