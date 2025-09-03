https://raw.githubusercontent.com/danko1981/gis_requirements/refs/heads/main/nginx/alterations.conf
#!/bin/bash
# Master setup script for GIS VMs.
# This script ensures proper execution context, permissions, and logging.

# --- Configuration ---
# IMPORTANT: Replace these URLs with the raw content URLs of your scripts and config files
RESIZE_SCRIPT_URL="https://raw.githubusercontent.com/danko1981/gis_requirements/refs/heads/main/resize_root_lvm.sh"
GIS_SCRIPT_URL="https://raw.githubusercontent.com/danko1981/gis_requirements/refs/heads/main/install_requirements.sh"

# Array of NGINX config file URLs
NGINX_CONFIG_URLS=(
    "https://raw.githubusercontent.com/danko1981/gis_requirements/refs/heads/main/nginx/alterations.conf"
    "https://raw.githubusercontent.com/danko1981/gis_requirements/refs/heads/main/nginx/geocoding.conf"
    "https://raw.githubusercontent.com/danko1981/gis_requirements/refs/heads/main/nginx/geoserver.conf"
    "https://raw.githubusercontent.com/danko1981/gis_requirements/refs/heads/main/nginx/routing.conf"
    "https://raw.githubusercontent.com/danko1981/gis_requirements/refs/heads/main/nginx/ums.conf"
)

# --- Setup ---
# Define a log file for the master script's execution trace
MASTER_LOG_FILE="/var/log/master_setup.log"
# Create temporary local paths for the scripts
LOCAL_RESIZE_SCRIPT="/tmp/resize_root_lvm.sh"
LOCAL_GIS_SCRIPT="/tmp/install_requirements.sh"
NGINX_CONFIG_DIR="/etc/nginx/conf.d"

# Redirect all stdout and stderr to the log file and also to the console
exec > >(tee -a ${MASTER_LOG_FILE}) 2>&1

echo "--- Starting Master Setup Script at $(date) ---"
echo "Running as user: $(whoami)"

# --- Pre-flight Checks ---
# 1. Verify root privileges
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root. The CustomScriptExtension should handle this automatically. Exiting."
   exit 1
fi
echo "Root privileges confirmed."

# --- Helper Function ---
# Function to download a file and handle errors
download_file() {
    local url=$1
    local local_path=$2
    local is_script=$3

    echo "Downloading file from ${url} to ${local_path}..."
    # Use curl with -f to fail silently on server errors (like 404) and -s for silent mode
    curl -s -f -L -o "${local_path}" "${url}" # Added -L to follow redirects
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Failed to download file from ${url}. Please check the URL and network connectivity. Exiting."
        exit 1
    fi
    echo "Download successful."

    if [[ "$is_script" = true ]]; then
        echo "Setting execute permissions on ${local_path}..."
        chmod +x "${local_path}"
        if [[ $? -ne 0 ]]; then
            echo "ERROR: Failed to set execute permissions on ${local_path}. Exiting."
            exit 1
        fi
        echo "Script ${local_path} is now ready to be executed."
    fi
}


# --- Main Execution Flow ---

# Step 1: Download and run the LVM resize script
echo ""
echo "--- Section 1: LVM Partition Resizing ---"
download_file "${RESIZE_SCRIPT_URL}" "${LOCAL_RESIZE_SCRIPT}" true

echo "Executing LVM resize script: ${LOCAL_RESIZE_SCRIPT}..."
# The sub-script will create its own log at /var/log/resize_lvm.log
bash "${LOCAL_RESIZE_SCRIPT}"
if [[ $? -ne 0 ]]; then
    echo "ERROR: The LVM resize script exited with a non-zero status. Please check its log at /var/log/resize_lvm.log for details. Exiting master script."
    exit 1
fi
echo "LVM resize script completed successfully."


# Step 2: Download and run the GIS installation script
echo ""
echo "--- Section 2: GIS Application Installation ---"
download_file "${GIS_SCRIPT_URL}" "${LOCAL_GIS_SCRIPT}" true

echo "Executing GIS installation script: ${LOCAL_GIS_SCRIPT}..."
bash "${LOCAL_GIS_SCRIPT}"
if [[ $? -ne 0 ]]; then
    echo "ERROR: The GIS installation script exited with a non-zero status. Exiting master script."
    exit 1
fi
echo "GIS installation script completed successfully."


# Step 3: Download and install NGINX configuration files
echo ""
echo "--- Section 3: NGINX Configuration ---"
if ! command -v nginx &> /dev/null; then
    echo "WARNING: NGINX is not installed. Skipping NGINX configuration."
else
    if [ ! -d "${NGINX_CONFIG_DIR}" ]; then
        echo "ERROR: NGINX config directory ${NGINX_CONFIG_DIR} does not exist. Please ensure NGINX is installed correctly. Exiting."
        exit 1
    fi

    for config_url in "${NGINX_CONFIG_URLS[@]}"; do
        file_name=$(basename "${config_url}")
        local_path="${NGINX_CONFIG_DIR}/${file_name}"
        download_file "${config_url}" "${local_path}" false
    done

    echo "All NGINX configuration files downloaded."
    echo "Testing NGINX configuration..."
    nginx -t
    if [[ $? -ne 0 ]]; then
        echo "ERROR: NGINX configuration test failed. Please check the downloaded .conf files for errors. Not restarting NGINX."
        exit 1
    fi

    echo "NGINX configuration is valid. Restarting NGINX service..."
    systemctl restart nginx
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Failed to restart NGINX service."
        exit 1
    fi
    echo "NGINX service restarted successfully."
fi

echo ""
echo "--- Master Setup Script finished successfully at $(date) ---"





