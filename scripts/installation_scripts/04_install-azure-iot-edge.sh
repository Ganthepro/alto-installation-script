#! /bin/bash

# check ubuntu version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
fi

if [ "$OS" != "ubuntu" ]; then
    echo "This script is only supported on Ubuntu"
    exit 1
fi

# if ubuntu version is 24.04, run the following commands
if [ "$(echo "$VERSION_ID == 24.04" | bc -l)" -eq 1 ]; then
    wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb
fi

# if ubuntu version is 22.04, run the following commands
if [ "$(echo "$VERSION_ID == 22.04" | bc -l)" -eq 1 ]; then
    wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb
fi

# if ubuntu version is 20.04, run the following commands
if [ "$(echo "$VERSION_ID == 20.04" | bc -l)" -eq 1 ]; then
    wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb
fi

# install moby engine
sudo apt-get update
sudo apt-get install -y moby-engine

# create or update docker daemon.json
sudo mkdir -p /etc/docker
sudo bash -c 'echo -e "{\n  \"log-driver\": \"local\",\n  \"log-opts\": {\n    \"max-size\": \"10m\",\n    \"max-file\": \"3\"\n  }\n}" > /etc/docker/daemon.json'

# restart docker service
sudo systemctl restart docker

# Install the IoT Edge runtime
# if ubuntu version is 22.04 or higher, run the following commands
if [ "$(echo "$VERSION_ID >= 22.04" | bc -l)" -eq 1 ]; then
    sudo apt-get update; \
    sudo apt-get install -y aziot-edge
fi

# if ubuntu version is 20.04, run the following commands
if [ "$(echo "$VERSION_ID == 20.04" | bc -l)" -eq 1 ]; then
    sudo apt-get update; \
    sudo apt-get install -y aziot-edge defender-iot-micro-agent-edge
fi

# load environment variables
source $WORKING_DIR/.env

sudo iotedge config mp --connection-string $IOT_HUB_DEVICE_CONNECTION_STRING
sudo iotedge config apply
