#!/bin/bash

# This script initializes and updates all git submodules for the Alto CERO infrastructure
# It should be run before the main installation process

echo "Initializing git submodules..."
git submodule init

echo "Updating git submodules recursively..."
git submodule update --recursive

# Check if we're in development mode
if [ "$1" = "--dev" ]; then
    echo "Development mode detected. Checking out dev branch for all submodules..."
    git submodule foreach --recursive git checkout dev
fi

echo "Submodule initialization complete." 