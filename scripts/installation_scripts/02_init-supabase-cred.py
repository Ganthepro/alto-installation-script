#!/usr/bin/env python3
"""
Supabase Credentials Generator

This script generates a JWT secret and corresponding API keys for Supabase authentication.
It updates the specified .env file with the new credentials.

Usage:
    python 02_init-supabase-cred.py <path/to/.env> <site_id>

Arguments:
    env_path    Path to the .env file to update
    site_id     Site ID to update in site configuration

Example:
    python 02_init-supabase-cred.py .env.local cp9
"""

import os
import sys
import re
import secrets
import string
import time
import jwt
import argparse
import yaml
import requests

def update_supabase_env_file(env_path, jwt_secret, anon_key, service_key):
    """Update the .env file with new keys."""
    try:
        # Check if .env file exists
        if not os.path.exists(env_path):
            print(f"🔎 Warning: .env file not found at {env_path}")
            template_path = os.path.join(os.path.dirname(env_path), '.env.template')
            if os.path.exists(template_path):
                with open(template_path, 'r') as src, open(env_path, 'w') as dst:
                    dst.write(src.read())
                print(f"✅ Created {env_path} from {template_path}")
            else:
                print(f"🔴 Warning: No .env file found at {env_path} and no template available")
                return
        
        # Read the existing content
        with open(env_path, 'r') as file:
            env_content = file.read()
        
        # Replace the keys using regex
        env_content = re.sub(r'^JWT_SECRET=.*$', f'JWT_SECRET={jwt_secret}', env_content, flags=re.MULTILINE)
        env_content = re.sub(r'^ANON_KEY=.*$', f'ANON_KEY={anon_key}', env_content, flags=re.MULTILINE)
        env_content = re.sub(r'^SERVICE_ROLE_KEY=.*$', f'SERVICE_ROLE_KEY={service_key}', env_content, flags=re.MULTILINE)
        
        # If the keys don't exist, append them to the file
        if 'JWT_SECRET=' not in env_content:
            env_content += f'\nJWT_SECRET={jwt_secret}\n'
        if 'ANON_KEY=' not in env_content:
            env_content += f'\nANON_KEY={anon_key}\n'
        if 'SERVICE_ROLE_KEY=' not in env_content:
            env_content += f'\nSERVICE_ROLE_KEY={service_key}\n'
        
        with open(env_path, 'w') as file:
            file.write(env_content)
        
        print('🔐 Updated .env file with new JWT secret and API keys')
    except Exception as e:
        print(f'Error updating .env file: {str(e)}')
        sys.exit(1)

def update_alto_env_file(anon_key):
    """Update the main .env file with the new Supabase ANON key."""
    # working_dir = os.environ.get('WORKING_DIR', os.getcwd())
    # env_path = os.path.join(working_dir, '.env')
    env_path = os.path.join('.env.alto')
    
    try:
        # Check if .env file exists
        if not os.path.exists(env_path):
            # If not, create it from .env.template if possible
            print(f"🔎 Warning: .env file not found at {env_path}")
            template_path = os.path.join('.env.template')
            if os.path.exists(template_path):
                with open(template_path, 'r') as src, open(env_path, 'w') as dst:
                    dst.write(src.read())
                print(f"✅ Created {env_path} from {template_path}")
            else:
                print(f"🔴 Warning: No .env file found at {env_path} and no template available")
                return
        
        # Read the existing content
        with open(env_path, 'r') as file:
            env_content = file.read()
        
        # Update the VITE_SUPABASE_ANON_KEY using regex
        env_content = re.sub(r'^VITE_SUPABASE_ANON_KEY=.*$', f'VITE_SUPABASE_ANON_KEY={anon_key}', 
                             env_content, flags=re.MULTILINE)
        
        # If the key doesn't exist, append it to the file
        if 'VITE_SUPABASE_ANON_KEY=' not in env_content:
            env_content += f'\nVITE_SUPABASE_ANON_KEY={anon_key}\n'
        
        # Write the updated content back to the file
        with open(env_path, 'w') as file:
            file.write(env_content)
        
        print(f'✅ Updated main .env file with new Supabase ANON key')
    except Exception as e:
        print(f'Error updating main .env file: {str(e)}')

def update_supabase_agent_config(site_id, anon_key):
    """Update the site configuration with Supabase ANON key."""
    # working_dir = os.environ.get('WORKING_DIR', os.getcwd())
    # site_config_path = os.path.join(working_dir, 'site_configs', f'{site_id}.yaml')
    site_config_path = os.path.join(f'{site_id}.yaml')
    if not os.path.exists(site_config_path):
        print(f'Site configuration file not found: {site_config_path}')
        return
    
    try:
        # Load the site configuration
        with open(site_config_path, 'r') as file:
            site_config = yaml.safe_load(file)
        
        # Check if volttron_agents section exists, if not create it
        if 'volttron_agents' not in site_config:
            site_config['volttron_agents'] = {}
        
        # Check if supabase section exists, if not create it
        if 'supabase' not in site_config['volttron_agents']:
            site_config['volttron_agents']['supabase'] = {
                'url': "http://0.0.0.0:8000/",
                'key': "YOUR_SUPABASE_ANON_KEY",
                'flush_interval': 2,  # seconds
                'check_interval': 10
            }
        
        # Update the ANON key
        site_config['volttron_agents']['supabase']['key'] = anon_key
        
        # Save the updated configuration
        with open(site_config_path, 'w') as file:
            yaml.dump(site_config, file, default_flow_style=False, sort_keys=False)
        
        print(f'✅ Updated Supabase ANON key in {site_id} site configuration')
    except Exception as e:
        print(f'Error updating site configuration: {str(e)}')

def main():
    parser = argparse.ArgumentParser(description='Generate Supabase JWT secret and API keys')
    parser.add_argument('env_path', help='Path to the .env file to update')
    parser.add_argument('site_id', help='Site ID to update in site configuration')
    parser.add_argument('token', help='For get supabase credentials token from API')
    args = parser.parse_args()
    
    env_path = args.env_path
    site_id = args.site_id
    token = args.token
    # Check if the .env file exists
    if not os.path.exists(env_path):
        # Try to copy from .env.example if it exists
        env_example_path = os.path.join(os.path.dirname(env_path), '.env.example')
        if os.path.exists(env_example_path):
            try:
                with open(env_example_path, 'r') as src, open(env_path, 'w') as dst:
                    dst.write(src.read())
                print(f"Created {env_path} from {env_example_path}")
            except Exception as e:
                print(f"Error copying .env.example to {env_path}: {str(e)}")
                sys.exit(1)
        else:
            print(f'Error: .env file not found at {env_path}')
            print('Usage: python 02_init-supabase-cred.py <path/to/.env> <site_id>')
            sys.exit(1)
    
    # Generate the secret and keys
    response = requests.get('https://iot-api.edusaig.com/api/config/supabase-cred/', headers={'Authorization': f'Bearer {token}', 'accept': 'application/json'})
    data = response.json()
    jwt_secret = data['jwt_secret']
    anon_key = data['anon_key']
    service_key = data['service_key']
    
    # If jwt returns bytes (depends on version), decode to string
    if isinstance(anon_key, bytes):
        anon_key = anon_key.decode('utf-8')
    if isinstance(service_key, bytes):
        service_key = service_key.decode('utf-8')
    
    # Update the supabase/docker/.env file
    update_supabase_env_file(env_path, jwt_secret, anon_key, service_key)

    # Update Alto .env file
    # update_alto_env_file(anon_key)

    # Update the site configuration
    update_supabase_agent_config(site_id, anon_key)
    
    # Output the generated values
    print('✅ Generated new Supabase authentication keys:')
    print('=============================================')
    print(f'JWT_SECRET: {jwt_secret}')
    print(f'ANON_KEY: {anon_key}')
    print(f'SERVICE_ROLE_KEY: {service_key}')
    print('=============================================')
    print('These values have been updated in your .env file.')
    print('Remember to restart your Supabase services for changes to take effect:')
    print('docker compose down && docker compose up -d')

if __name__ == '__main__':
    main()