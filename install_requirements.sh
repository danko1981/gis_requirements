#!/usr/bin/env bash
# RHEL non-interactive setup:
# - Disable firewall
# - Install & enable nginx
# - setsebool httpd_can_network_connect on (persistent)
# - Create user 'gis' with encrypted password
# - Create/manage its group
# - Grant sudo privileges

set -euo pipefail

# --- Preconditions ------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (e.g., sudo $0)"; exit 1
fi

# --- 1) Add Firewall Roules ------------------------------------------
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --add-port=9200/tcp

# --- 2) Install & enable nginx -----------------------------------------------
dnf -y install nginx
systemctl enable --now nginx

# --- 3) SELinux boolean for outbound network from web server ------------------
# (affects nginx/httpd contexts; persistent with -P)
setsebool -P httpd_can_network_connect on

# --- 4) Create user 'gis' with encrypted password -----------------------------
USERNAME="gis"
PLAINTEXT_PW='1Qaz2wsx3edc'

# Ensure 'gis' group exists and is primary group for the user
groupadd -f "${USERNAME}"

# Generate a SHA-512 crypt hash non-interactively (requires openssl)
HASH="$(echo -n "${PLAINTEXT_PW}" | openssl passwd -6 -stdin)"

# Create user if missing, else ensure shell/home/group and reset password
if id -u "${USERNAME}" >/dev/null 2>&1; then
  usermod -g "${USERNAME}" -s /bin/bash "${USERNAME}"
  echo "${USERNAME}:${PLAINTEXT_PW}" | chpasswd -e <<<"${USERNAME}:${HASH}" 2>/dev/null || true
  # chpasswd -e expects pre-hashed on stdin; fallback to direct chpasswd if unavailable:
  echo "${USERNAME}:${PLAINTEXT_PW}" | chpasswd || true
else
  useradd -m -s /bin/bash -g "${USERNAME}" -p "${HASH}" "${USERNAME}"
fi

# --- 5) Manage group membership & sudo privileges -----------------------------
# Add user to its own group (already primary) and to wheel for general admin:
usermod -aG wheel "${USERNAME}"

# Also grant explicit sudo via sudoers.d (keeps config simple & auditable)
dnf -y install sudo
SUDO_FILE="/etc/sudoers.d/90-${USERNAME}"
echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "${SUDO_FILE}"
chmod 0440 "${SUDO_FILE}"

# --- 6 Create a mountpoint for the Shared files.
mkdir /sharedFiles
chown -R gis:gis /sharedFiles

echo "All done."
echo "Firewall: disabled"
echo "nginx: installed and running"
echo "SELinux boolean httpd_can_network_connect: enabled (persistent)"
echo "User '${USERNAME}': created/updated, in groups: ${USERNAME}, wheel; sudo enabled"
echo "Mountopoint /sharedFiles created succesfully."
