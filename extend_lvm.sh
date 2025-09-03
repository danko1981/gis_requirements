#!/bin/bash
# This script resizes key LVM logical volumes on a RHEL-based system to proportionally use available disk space.

# --- Configuration ---
# Define the logical volumes to resize and the percentage of the TOTAL FREE SPACE to allocate to each.
# The LV names here are the short names (e.g., 'rootlv', 'varlv').
# The script will find the Volume Group automatically.
# IMPORTANT: The percentages should add up to 100 to use all available free space.
declare -A LV_RESIZE_PERCENTAGES=(
    ["rootlv"]=20
    ["varlv"]=10
    ["homelv"]=40
    ["usrlv"]=20
    ["tmplv"]=10
)

# Log file for debugging
LOG_FILE="/var/log/resize_lvm.log"
# Redirect stdout and stderr to the log file and the console
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "--- Starting LVM resize script at $(date) ---"

# --- Function to resize a filesystem ---
resize_filesystem() {
    local mount_point=$1
    echo "Resizing filesystem for ${mount_point}..."
    local fs_type
    fs_type=$(findmnt -n -o FSTYPE "${mount_point}")
    echo "Filesystem type is '${fs_type}'."

    case "$fs_type" in
        xfs)
            xfs_growfs "${mount_point}"
            ;;
        ext4|ext3)
            # resize2fs needs the device path, not the mount point
            local device_path
            device_path=$(findmnt -n -o SOURCE "${mount_point}")
            resize2fs "${device_path}"
            ;;
        *)
            echo "WARNING: Unsupported filesystem type '${fs_type}' for ${mount_point}. Filesystem cannot be resized."
            return 1
            ;;
    esac

    if [[ $? -ne 0 ]]; then
        echo "ERROR: Failed to resize filesystem for ${mount_point}."
        return 1
    fi
    echo "Successfully resized filesystem for ${mount_point}."
    return 0
}

# --- Sanity check the percentages ---
TOTAL_PERCENTAGE=0
for P in "${LV_RESIZE_PERCENTAGES[@]}"; do
    TOTAL_PERCENTAGE=$((TOTAL_PERCENTAGE + P))
done

if [[ "$TOTAL_PERCENTAGE" -ne 100 ]]; then
    echo "ERROR: The sum of percentages in LV_RESIZE_PERCENTAGES is ${TOTAL_PERCENTAGE}, but it must be 100. Exiting."
    exit 1
fi
echo "Percentage configuration is valid (sums to 100)."


# --- Step 1: Discover the physical volume, device, and partition for the root VG ---
echo "Discovering root filesystem's LVM configuration..."
ROOT_LV_DEVICE=$(findmnt -n -o SOURCE /)
if [[ ! -e "$ROOT_LV_DEVICE" ]]; then
    echo "ERROR: Could not determine the root logical volume device. Exiting."
    exit 1
fi

VG_NAME=$(lvs --noheadings -o vg_name "${ROOT_LV_DEVICE}" | xargs)
if [[ -z "$VG_NAME" ]]; then
    echo "ERROR: Could not determine the volume group for root filesystem. Exiting."
    exit 1
fi
echo "Detected Volume Group: ${VG_NAME}"

PV_NAME=$(pvs --noheadings -o pv_name -S "vg_name=${VG_NAME}" | head -n 1 | xargs)
if [[ -z "$PV_NAME" ]]; then
    echo "ERROR: Could not determine the Physical Volume for VG '${VG_NAME}'. Exiting."
    exit 1
fi
echo "Detected Physical Volume: ${PV_NAME}"

# Extract device name (e.g., /dev/sda) and partition number (e.g., 2)
# This is a more robust way to get the base device name and partition number
DEVICE_NAME="/dev/$(lsblk -dno pkname "${PV_NAME}")"
PARTITION_NUMBER=$(echo "${PV_NAME}" | sed 's/.*\([0-9]\+\)$/\1/')
echo "Detected Device: ${DEVICE_NAME}, Partition Number: ${PARTITION_NUMBER}"


# --- Step 2: Grow the partition to fill the disk ---
echo "Attempting to grow partition ${DEVICE_NAME} ${PARTITION_NUMBER}..."
# The growpart command needs to be installed (comes with cloud-utils-growpart)
if ! command -v growpart &> /dev/null; then
    echo "'growpart' command not found. Installing cloud-utils-growpart..."
    yum install -y cloud-utils-growpart
fi

growpart "${DEVICE_NAME}" "${PARTITION_NUMBER}"
if [[ $? -ne 0 ]]; then
    echo "WARNING: 'growpart' failed. This is often okay if the partition is already at its maximum size."
else
    echo "Partition grown successfully."
    # After growing the partition, tell the kernel to re-read the partition table
    echo "Re-reading partition table with partprobe..."
    partprobe "${DEVICE_NAME}"
fi


# --- Step 3: Resize the Physical Volume ---
echo "Resizing physical volume ${PV_NAME} to use the new space..."
pvresize "${PV_NAME}"
if [[ $? -ne 0 ]]; then
    echo "ERROR: 'pvresize' failed. Cannot continue."
    exit 1
fi
echo "Physical volume resized successfully."


# --- Step 4: Calculate free space ---
echo "Calculating available space..."
# Use vgs for reliable, script-friendly output of free space in PE (Physical Extents)
# This fixes the "incompatible options" error from vgdisplay
TOTAL_FREE_PE=$(vgs --noheadings --units e -o vg_free_count "${VG_NAME}" | xargs)


if [[ "$TOTAL_FREE_PE" -le 0 ]]; then
    echo "No free space available in volume group '${VG_NAME}'. Nothing to extend."
    echo "--- Script finished ---"
    exit 0
fi
echo "Total free space in '${VG_NAME}': ${TOTAL_FREE_PE} extents."


# --- Step 5: Loop through ACTUAL LVs, match against config, and resize ---
echo "Discovering and resizing logical volumes in VG '${VG_NAME}'..."
ALL_LVS_IN_VG=$(lvs --noheadings -o lv_name "${VG_NAME}" | xargs)

for LV_NAME in ${ALL_LVS_IN_VG}; do
    # Check if this discovered LV is one we want to resize
    if [[ -v "LV_RESIZE_PERCENTAGES[${LV_NAME}]" ]]; then
        PERCENTAGE=${LV_RESIZE_PERCENTAGES[$LV_NAME]}
        EXTENTS_TO_ADD=$(( (TOTAL_FREE_PE * PERCENTAGE) / 100 ))
        LV_PATH="/dev/${VG_NAME}/${LV_NAME}"
        MOUNT_POINT=$(findmnt -n -o TARGET "${LV_PATH}")

        echo "--- Processing ${LV_NAME} ---"
        echo "Found matching LV in configuration. Target Path: ${LV_PATH}, Mount Point: ${MOUNT_POINT}"
        echo "Will be extended by ${PERCENTAGE}% of total free space (~${EXTENTS_TO_ADD} extents)."

        if [[ "$EXTENTS_TO_ADD" -gt 0 ]]; then
            lvextend -l "+${EXTENTS_TO_ADD}" "${LV_PATH}"
            if [[ $? -eq 0 ]]; then
                echo "Successfully extended logical volume '${LV_NAME}'."
                # Resize filesystem immediately after extending LV
                if [[ -n "$MOUNT_POINT" ]]; then
                    resize_filesystem "${MOUNT_POINT}"
                else
                    echo "WARNING: No mount point found for ${LV_PATH}, cannot resize filesystem."
                fi
            else
                echo "ERROR: Failed to extend logical volume '${LV_NAME}'."
            fi
        else
            echo "No extents to add for '${LV_NAME}' (calculation resulted in zero). Skipping extension."
        fi
        echo "--------------------------"
    else
        echo "--- Skipping ${LV_NAME} (not in configuration map) ---"
    fi
done

echo "--- LVM resize script finished at $(date) ---"
echo "Final disk usage:"
df -h
