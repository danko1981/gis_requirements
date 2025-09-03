#!/bin/bash
# Master script to set up a GIS VM:
# 1. Resize the root LVM partition.
# 2. Run the original GIS software installation script.

# URL for the LVM resize script
RESIZE_SCRIPT_URL="https://raw.githubusercontent.com/danko1981/gis_requirements/refs/heads/main/install_requirements.sh"

# URL for GIS requirements installation script
GIS_SCRIPT_URL="https://raw.githubusercontent.com/danko1981/gis_requirements/refs/heads/main/install_requirements.sh"

# --- Run LVM Resize ---
echo "Downloading and running LVM resize script..."
curl -sSL ${RESIZE_SCRIPT_URL} | bash
echo "LVM resize script finished."

# --- Run GIS Installation ---
echo "Downloading and running GIS installation script..."
curl -sSL ${GIS_SCRIPT_URL} | bash
echo "GIS installation script finished."

echo "Master setup script complete."
