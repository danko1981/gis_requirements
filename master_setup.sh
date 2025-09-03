#!/bin/bash
# Master setup script for GIS VMs.
# This script ensures proper execution context, permissions, and logging.

# --- Configuration ---
# IMPORTANT: Replace this URL with the raw content URL of your resize_root_lvm.sh script
RESIZE_SCRIPT_URL="https://raw.githubusercontent.com/danko1981/gis_requirements/refs/heads/main/install_requirements.sh"
GIS_SCRIPT_URL="https://raw.githubusercontent.com/danko1981/gis_requirements/refs/heads/main/install_requirements.sh"

# --- Setup ---
# Define a log file for the master script's execution trace
MASTER_LOG_FILE="/var/log/master_setup.log"
# Create temporary local paths for the scripts
LOCAL_RESIZE_SCRIPT="/tmp/resize_root_lvm.sh"
LOCAL_GIS_SCRIPT="/tmp/install_requirements.sh"

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
# Function to download a script, make it executable, and handle errors
download_and_prep_script() {
    local url=$1
    local local_path=$2

    echo "Downloading script from ${url} to ${local_path}..."
    # Use curl with -f to fail silently on server errors (like 404) and -s for silent mode
    curl -s -f -o "${local_path}" "${url}"
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Failed to download script from ${url}. Please check the URL and network connectivity. Exiting."
        exit 1
    fi
    echo "Download successful."

    echo "Setting execute permissions on ${local_path}..."
    chmod +x "${local_path}"
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Failed to set execute permissions on ${local_path}. Exiting."
        exit 1
    fi
    echo "Script ${local_path} is now ready to be executed."
}

# --- Main Execution Flow ---

# Step 1: Download and run the LVM resize script
echo ""
echo "--- Section 1: LVM Partition Resizing ---"
download_and_prep_script "${RESIZE_SCRIPT_URL}" "${LOCAL_RESIZE_SCRIPT}"

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
download_and_prep_script "${GIS_SCRIPT_URL}" "${LOCAL_GIS_SCRIPT}"

echo "Executing GIS installation script: ${LOCAL_GIS_SCRIPT}..."
bash "${LOCAL_GIS_SCRIPT}"
if [[ $? -ne 0 ]]; then
    echo "ERROR: The GIS installation script exited with a non-zero status. Exiting master script."
    exit 1
fi
echo "GIS installation script completed successfully."


echo ""
echo "--- Master Setup Script finished successfully at $(date) ---"
