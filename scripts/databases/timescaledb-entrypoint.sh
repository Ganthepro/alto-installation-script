#!/bin/bash

# Add this line before starting PostgreSQL
export POSTGRES_ARGS="-c shared_preload_libraries=timescaledb"

# Function to start PostgreSQL in the background
start_postgres() {
    docker-entrypoint.sh postgres &
    while ! pg_isready -U postgres; do
        echo "Waiting for PostgreSQL to start..."
        sleep 1
    done
}

# Start PostgreSQL
start_postgres

# Install TimescaleDB extension
echo "Installing TimescaleDB extension..."
psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"

# Run timescaledb-tune and apply recommendations
echo "Running timescaledb-tune..."
timescaledb-tune --quiet --yes

# Restart PostgreSQL to apply changes
echo "Restarting PostgreSQL to apply changes..."
pg_ctl -D /home/postgres/pgdata/data restart

# Wait for PostgreSQL to restart
sleep 5
while ! pg_isready -U postgres; do
    echo "Waiting for PostgreSQL to restart..."
    sleep 1
done

# Ensure TimescaleDB extension is created after restart
echo "Ensuring TimescaleDB extension is created after restart..."
psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"
psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit CASCADE;"

# Verify TimescaleDB extension and tuning
echo "Verifying TimescaleDB setup and tuning..."
psql -U postgres <<-EOSQL
    -- Check TimescaleDB extension
    SELECT extname, extversion FROM pg_extension WHERE extname LIKE 'timescale%';
    
    -- Check some important PostgreSQL settings
    SHOW max_connections;
    SHOW shared_buffers;
    SHOW effective_cache_size;
    SHOW maintenance_work_mem;
    SHOW timescaledb.max_background_workers;
    
    -- Check if TimescaleDB-specific settings are present
    SELECT name, setting 
    FROM pg_settings 
    WHERE name LIKE 'timescaledb%' 
    ORDER BY name;
EOSQL

# Keep the container running
echo "TimescaleDB setup complete. Container is now running."
tail -f /dev/null

