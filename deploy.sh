#!/bin/bash

# Interactive script to install nca-toolkit (latest) and Caddy for domain access on an Ubuntu VPS.
# Assumptions: Ubuntu-based VPS with at least 8GB RAM, 4 CPU cores, and 40GB free disk space.
# Dependencies: curl, docker, docker-compose, Caddy.
# Run with: chmod +x deploy.sh && ./deploy.sh

# Enable error handling
set -e

# Define LOG_FILE early to prevent tee errors
LOG_FILE="deploy.log"

# Function for logging with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check Bash environment
if [ -z "$BASH_VERSION" ]; then
    log "Error: Script must be run with Bash."
    exit 1
fi

# Function to prompt for input without default value
prompt() {
    local prompt_text="$1"
    read -p "$prompt_text: " input
    echo "$input"
}

# Instructions for Cloudflare R2 setup
log "Preparing to collect user configuration..."
echo "- Before proceeding, you need to set up a Cloudflare R2 bucket and generate the required credentials:"
echo "- Create a Cloudflare R2 bucket in your Cloudflare dashboard."
echo "- Generate an API Key for nca-toolkit (e.g., a 32-character alphanumeric string)."
echo "- Obtain S3-compatible credentials (Access Key, Secret Key) for R2."
echo "- Note the S3 Endpoint URL, Bucket Name, and Region (e.g., apac) from your R2 configuration."
echo "- Are you Ready ??? Press Enter to continue..."
read

# Collect user input
log "Collecting configuration from user..."
HOSTNAME_INPUT=$(prompt "Enter desired hostname for this VPS (e.g., myvps)")
TIMEZONE=$(prompt "Enter timezone (e.g., Asia/Jakarta)")
SWAP_SIZE=$(prompt "Enter swapfile size (e.g., 2G)")
NCA_API_KEY=$(prompt "Enter API Key for nca-toolkit (e.g., 3NHfia7KgkK26K4wLWE84vQFdF2495XU1)")
NCA_S3_ENDPOINT=$(prompt "Enter S3 Endpoint URL (e.g., https://a25e914db58f76a9bf7c2c9517b475f02.r2.cloudflarestorage.com)")
NCA_S3_ACCESS_KEY=$(prompt "Enter S3 Access Key (e.g., 267663438d579d8edba018240c9c730e3)")
NCA_S3_SECRET_KEY=$(prompt "Enter S3 Secret Key (e.g., 44185c6b00caff9e6822b8885d1ff8ce26635ebbab4c55959b08e528f1da4a414)")
NCA_S3_BUCKET=$(prompt "Enter S3 Bucket Name (e.g., automator)")
NCA_S3_REGION=$(prompt "Enter S3 Region (e.g., apac)")
NCA_DOMAIN=$(prompt "Enter domain for nca-toolkit (e.g., https://nca.example.com) - ensure A record points to this VPS IP")


# Validate user input (ensure critical fields are not empty)
if [ -z "$HOSTNAME_INPUT" ]; then
    log "Error: Hostname cannot be empty."
    exit 1
fi
if [ -z "$TIMEZONE" ]; then
    log "Error: Timezone cannot be empty."
    exit 1
fi
if [ -z "$SWAP_SIZE" ]; then
    log "Error: Swapfile size cannot be empty."
    exit 1
fi
if [ -z "$NCA_API_KEY" ]; then
    log "Error: API Key for nca-toolkit cannot be empty."
    exit 1
fi
if [ -z "$NCA_S3_ENDPOINT" ]; then
    log "Error: S3 Endpoint URL cannot be empty."
    exit 1
fi
if [ -z "$NCA_S3_ACCESS_KEY" ]; then
    log "Error: S3 Access Key cannot be empty."
    exit 1
fi
if [ -z "$NCA_S3_SECRET_KEY" ]; then
    log "Error: S3 Secret Key cannot be empty."
    exit 1
fi
if [ -z "$NCA_S3_BUCKET" ]; then
    log "Error: S3 Bucket Name cannot be empty."
    exit 1
fi
if [ -z "$NCA_S3_REGION" ]; then
    log "Error: S3 Region cannot be empty."
    exit 1
fi
if [ -z "$NCA_DOMAIN" ]; then
    log "Error: NCA Toolkit domain cannot be empty."
    exit 1
fi

# Default non-interactive configuration
NCA_PORT="8080" # This is the port NCA-Toolkit exposes inside Docker, proxied by Caddy
NCA_CPUS="2"
NCA_MEMORY="4G"
CLEAN_DOCKER="yes" # Option to clean up old Docker resources
NCA_DIR="/root/nca-toolkit"
NCA_MAX_QUEUE_LENGTH="10"
NCA_GUNICORN_WORKERS="4"
NCA_GUNICORN_TIMEOUT="300"

# Validate system prerequisites
log "Validating system prerequisites..."
if ! command -v curl >/dev/null 2>&1; then
    log "Error: curl not found. Please install curl first."
    exit 1
fi
# Using a minimum of 4GB for the base system + NCA-Toolkit (4GB) + Caddy
if [ "$(free -m | awk '/Mem:/ {print $2}')" -lt 4000 ]; then
    log "Error: Memory less than 4GB. At least 4GB recommended for base system and nca-toolkit."
    exit 1
fi
# NCA-Toolkit uses 2 CPUs by default, ensuring at least 4 for overall system health
if [ "$(nproc)" -lt 4 ]; then
    log "Error: Fewer than 4 CPU cores."
    exit 1
fi
# 20GB for OS + Docker + Caddy + logs + potential temp files
if [ "$(df -h / | awk 'NR==2 {print $4}' | grep -o '[0-9]\+')" -lt 20 ]; then
    log "Error: Less than 20GB free disk space."
    exit 1
fi

# Server preparation
log "Starting server preparation..."
log "Setting hostname to $HOSTNAME_INPUT..."
hostnamectl set-hostname "$HOSTNAME_INPUT" || { log "Error: Failed to set hostname."; exit 1; }

apt update && apt upgrade -y || { log "Error: Failed to update system."; exit 1; }
apt autoremove -y
timedatectl set-timezone "$TIMEZONE" || { log "Error: Failed to set timezone."; exit 1; }

if [ ! -f /swapfile ]; then
    log "Creating swapfile of size $SWAP_SIZE..."
    fallocate -l "$SWAP_SIZE" /swapfile || { log "Error: Failed to create swapfile."; exit 1; }
    chmod 600 /swapfile
    mkswap /swapfile
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    swapon /swapfile || { log "Error: Failed to activate swap."; exit 1; }
else
    log "Swapfile already exists, skipping creation."
fi

log "Installing Docker dependencies..."
apt-get install -y ca-certificates curl || { log "Error: Failed to install basic dependencies (ca-certificates, curl)."; exit 1; }
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc || { log "Error: Failed to download Docker GPG key."; exit 1; }
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
log "Installing Docker and Docker Compose plugin..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { log "Error: Failed to install Docker components."; exit 1; }

log "Installing Caddy web server..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https || { log "Error: Failed to install Caddy prerequisites."; exit 1; }
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg || { log "Error: Failed to download Caddy GPG key."; exit 1; }
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null || { log "Error: Failed to add Caddy repository."; exit 1; }
apt update || { log "Error: Failed to update apt after adding Caddy repo."; exit 1; }
apt install -y caddy || { log "Error: Failed to install Caddy."; exit 1; }
log "Caddy installation completed."

log "Server preparation completed."

# Clean up old Docker resources
if [ "$CLEAN_DOCKER" = "yes" ]; then
    log "Cleaning up old Docker resources..."
    docker system prune -af --volumes || { log "Error: Failed to clean Docker resources."; exit 1; }
else
    log "Skipping Docker resource cleanup."
fi

# Deploy nca-toolkit
log "Starting nca-toolkit deployment..."
mkdir -p "$NCA_DIR" && cd "$NCA_DIR" || { log "Error: Failed to create or change directory to $NCA_DIR."; exit 1; }
log "Creating .env file for nca-toolkit..."
cat <<EOF > .env
API_KEY=$NCA_API_KEY
S3_ENDPOINT_URL=$NCA_S3_ENDPOINT
S3_ACCESS_KEY=$NCA_S3_ACCESS_KEY
S3_SECRET_KEY=$NCA_S3_SECRET_KEY
S3_BUCKET_NAME=$NCA_S3_BUCKET
S3_REGION=$NCA_S3_REGION
MAX_QUEUE_LENGTH=$NCA_MAX_QUEUE_LENGTH
GUNICORN_WORKERS=$NCA_GUNICORN_WORKERS
GUNICORN_TIMEOUT=$NCA_GUNICORN_TIMEOUT
EOF
log "Creating docker-compose.yml for nca-toolkit..."
cat <<EOF > docker-compose.yml
services:
  nca-toolkit:
    image: stephengpope/no-code-architects-toolkit:latest
    ports:
      - "$NCA_PORT:8080" # Map internal 8080 to host $NCA_PORT
    env_file:
      - .env
    deploy:
      resources:
        limits:
          cpus: "$NCA_CPUS"
          memory: "$NCA_MEMORY"
    restart: unless-stopped
    user: root # Consider changing to a non-root user if image supports it
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
log "Running nca-toolkit container..."
docker compose up -d || { log "Error: Failed to run nca-toolkit Docker Compose."; exit 1; }
sleep 5 # Wait for container to start
if ! docker ps | grep -q "nca-toolkit-nca-toolkit"; then
    log "Error: nca-toolkit container is not running."
    exit 1
fi
log "nca-toolkit deployment completed."

# Configure Caddy
log "Configuring Caddy as reverse proxy for $NCA_DOMAIN..."
# Ensure .env files are secure BEFORE Caddy configuration
chmod 600 "$NCA_DIR/.env" || { log "Error: Failed to set permissions for $NCA_DIR/.env"; exit 1; }

# Create Caddyfile
cat <<EOF > /etc/caddy/Caddyfile
$NCA_DOMAIN {
    # Proxy requests to the nca-toolkit Docker container's exposed port on localhost
    reverse_proxy localhost:$NCA_PORT
    
    # Enable logging for troubleshooting
    log {
        output file /var/log/caddy/$NCA_DOMAIN.log
    }

    # Enable gzip compression
    encode gzip
}
EOF

# Ensure Caddy can write logs
mkdir -p /var/log/caddy || { log "Error: Failed to create Caddy log directory."; exit 1; }
chown caddy:caddy /var/log/caddy || { log "Error: Failed to set ownership for Caddy log directory."; exit 1; }
chmod 755 /var/log/caddy || { log "Error: Failed to set permissions for Caddy log directory."; exit 1; }

log "Enabling and reloading Caddy service..."
systemctl enable caddy || { log "Error: Failed to enable Caddy service."; exit 1; }
systemctl reload caddy || { log "Error: Failed to reload Caddy service."; exit 1; }
log "Caddy configuration completed. Your nca-toolkit should now be accessible via https://$NCA_DOMAIN"

log "Deployment fully completed!"
log "Please ensure that your domain ($NCA_DOMAIN) has an A record pointing to this VPS's IP address."
log "Caddy will automatically obtain an SSL certificate from Let's Encrypt."
