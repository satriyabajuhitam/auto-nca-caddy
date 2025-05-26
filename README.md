# Auto NCA Toolkit with Caddy

This repository provides an interactive Bash script to automate the deployment of `nca-toolkit` (a Dockerized application) and configure Caddy as a reverse proxy with automatic HTTPS (Let's Encrypt) on an Ubuntu VPS.

The script simplifies the setup process, from system preparation and Docker installation to Caddy configuration for secure domain access.

## ✨ Features

*   **Automated `nca-toolkit` Deployment:** Installs the latest `nca-toolkit` via Docker Compose.
*   **Automatic HTTPS with Caddy:** Configures Caddy web server to act as a reverse proxy, automatically obtaining and renewing SSL certificates from Let's Encrypt.
*   **Interactive Setup:** Guides you through collecting essential configuration details like hostname, timezone, Cloudflare R2 credentials, and your desired domain.
*   **System Preparation:** Handles system updates, swapfile creation, and Docker/Caddy dependencies installation.
*   **Secure Credential Handling:** Sets appropriate permissions for `.env` files containing sensitive API keys.

## ⚠️ Assumptions & Prerequisites

Before running this script, please ensure your VPS meets the following criteria:

*   **Operating System:** Ubuntu 20.04 LTS or 22.04 LTS (clean installation recommended).
*   **Hardware:**
    *   Minimum 8GB RAM (4GB for base system + 4GB for `nca-toolkit`).
    *   Minimum 4 CPU Cores.
    *   Minimum 40GB free disk space.
*   **Access:** You must have root access or `sudo` privileges.
*   **Domain Name:** A registered domain name (e.g., `nca.example.com`) whose `A` record points to the public IP address of your VPS. **DNS propagation must be complete before running the script.**
*   **Cloudflare R2 Credentials:** You must have already set up a Cloudflare R2 bucket and obtained the following:
    *   An API Key for `nca-toolkit` (a 32-character alphanumeric string recommended).
    *   S3-compatible Access Key.
    *   S3-compatible Secret Key.
    *   S3 Endpoint URL.
    *   S3 Bucket Name.
    *   S3 Region.

## 📦 Dependencies (Installed by Script)

The `deploy.sh` script will automatically install:

*   `curl`
*   `docker`
*   `docker-compose-plugin`
*   `caddy`

## 🚀 Installation Guide

Follow these steps to deploy `nca-toolkit` and Caddy on your Ubuntu VPS:

1.  **Connect to your VPS:**
    Open your terminal and connect to your VPS via SSH:
    ```bash
    ssh your_user@your_vps_ip
    ```
    If you're not `root`, switch to the root user or use `sudo` for the following steps.

2.  **Download the Script:**
    Download the `deploy.sh` script to your VPS:
    ```bash
    curl -sL https://raw.githubusercontent.com/satriyabajuhitam/auto-nca-caddy/main/deploy.sh -o deploy.sh
    ```

3.  **Make the Script Executable:**
    Give the script execution permissions:
    ```bash
    chmod +x deploy.sh
    ```

4.  **Run the Deployment Script:**
    Execute the script. It will guide you through the configuration process interactively.
    ```bash
    sudo ./deploy.sh
    ```

### Interactive Configuration Prompts

The script will prompt you for the following information:

*   **Enter desired hostname for this VPS:** (e.g., `myvps`) - This will set the hostname of your server.
*   **Enter timezone:** (e.g., `Asia/Jakarta`) - Sets the system's timezone.
*   **Enter swapfile size:** (e.g., `2G`) - Creates a swap file for better memory management.
*   **Enter API Key for nca-toolkit:** (e.g., `3NHfia7KgkK26K4wLWE84vQFdF2495XU1`) - Your `nca-toolkit` API key.
*   **Enter S3 Endpoint URL:** (e.g., `https://a25e914db58f76a9bf7c2c9517b475f02.r2.cloudflarestorage.com`) - Cloudflare R2 S3 endpoint.
*   **Enter S3 Access Key:** (e.g., `267663438d579d8edba018240c9c730e3`) - Cloudflare R2 S3 access key.
*   **Enter S3 Secret Key:** (e.g., `44185c6b00caff9e6822b8885d1ff8ce26635ebbab4c55959b08e528f1da4a414`) - Cloudflare R2 S3 secret key.
*   **Enter S3 Bucket Name:** (e.g., `automator`) - Cloudflare R2 bucket name.
*   **Enter S3 Region:** (e.g., `apac`) - Cloudflare R2 bucket region.
*   **Enter domain for nca-toolkit:** (e.g., `https://nca.example.com`) - This is the domain Caddy will use for HTTPS access to `nca-toolkit`. **Ensure your DNS A record points to your VPS IP.**

## ✅ Post-Installation Checks

After the script completes, you can verify the deployment:

1.  **Check Caddy Status:**
    ```bash
    sudo systemctl status caddy
    ```
    It should show `active (running)`.

2.  **Check Docker Containers:**
    ```bash
    sudo docker ps
    ```
    You should see `nca-toolkit-nca-toolkit-1` container running.

3.  **Access NCA Toolkit:**
    Open your web browser and navigate to the domain you configured (e.g., `https://nca.example.com`). Caddy should have automatically provisioned an SSL certificate, and you should see the `nca-toolkit` interface.

## 📝 Important Notes

*   **No Firewall (UFW):** This script *does not* configure UFW or any other firewall rules. It explicitly removes previous UFW configurations if present. You are responsible for setting up any necessary firewall rules (e.g., `ufw allow 80,443/tcp` for web traffic, and your SSH port if you enable UFW manually later).
*   **Docker Image Tag:** The script uses `stephengpope/no-code-architects-toolkit:latest`. While convenient, using `latest` means the image can change without notice, potentially introducing breaking changes. For production environments, it's generally recommended to use a specific version tag.
*   **Docker Container User:** The `nca-toolkit` container runs as `root` inside Docker. For enhanced security, consider modifying the `docker-compose.yml` to use a non-root user if the `nca-toolkit` image supports it.
*   **DNS Propagation:** Caddy relies on your domain's A record pointing correctly to your VPS IP. If Caddy fails to obtain an SSL certificate, it's often due to DNS not being fully propagated. Give it some time and try restarting Caddy (`sudo systemctl restart caddy`).
*   **No Backup Strategy:** This script does not include any backup solutions for your `nca-toolkit` data or configurations. Implement a separate backup strategy for your critical data.

## 🐛 Troubleshooting

*   **Check `deploy.log`:** For any script execution errors, review the `deploy.log` file in the directory where you ran the script.
*   **Caddy Logs:** Check Caddy's logs for issues with domain resolution or SSL certificate acquisition:
    ```bash
    sudo journalctl -u caddy --no-pager
    sudo tail -f /var/log/caddy/your-nca-domain.com.log
    ```
*   **Docker Logs:** Check `nca-toolkit` container logs for application-specific errors:
    ```bash
    sudo docker logs nca-toolkit-nca-toolkit-1
    ```
*   **Restart Services:** Sometimes, a simple restart can resolve transient issues:
    ```bash
    sudo systemctl restart caddy
    sudo docker compose -f /root/nca-toolkit/docker-compose.yml restart
    ```

## 🤝 Contributing

Feel free to open issues or submit pull requests if you have suggestions for improvements or bug fixes.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
