#!/bin/bash
# =============================================================================
# prepare_sd.sh
# Run this on your host machine AFTER flashing DietPi to the SD card.
# Usage: sudo bash prepare_sd.sh <path_to_boot_partition> <path_to_teleporter_zip> [config.properties]
# Example: sudo bash prepare_sd.sh /media/user/bootfs ~/pihole-teleporter.zip ~/pihole.properties
# =============================================================================

set -e

BOOT="${1}"
TELEPORTER_ZIP="${2}"
PROPS_FILE="${3}"

if [[ -z "$BOOT" || -z "$TELEPORTER_ZIP" ]]; then
    echo "Usage: sudo bash prepare_sd.sh <boot_partition_path> <teleporter_zip_path> [config.properties]"
    exit 1
fi

if [[ ! -d "$BOOT" ]]; then
    echo "ERROR: Boot partition not found at: $BOOT"
    exit 1
fi

if [[ ! -f "$TELEPORTER_ZIP" ]]; then
    echo "ERROR: Teleporter zip not found at: $TELEPORTER_ZIP"
    exit 1
fi

DIETPI_TXT="$BOOT/dietpi.txt"

if [[ ! -f "$DIETPI_TXT" ]]; then
    echo "ERROR: dietpi.txt not found at $DIETPI_TXT — is this the right partition?"
    exit 1
fi

# =============================================================================
# Load properties file if provided
# =============================================================================
if [[ -n "$PROPS_FILE" ]]; then
    if [[ ! -f "$PROPS_FILE" ]]; then
        echo "ERROR: Properties file not found at: $PROPS_FILE"
        exit 1
    fi
    echo "==> Loading configuration from $PROPS_FILE..."
    # Source only KEY=VALUE lines, ignoring comments and blanks
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | tr -d '[:space:]')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        declare "$key=$value"
    done < "$PROPS_FILE"
    echo "==> Properties loaded."
    echo ""
fi

# =============================================================================
# Prompt for any values not already set by properties file
# =============================================================================
echo "==> Configuration"
echo "    Press Enter to accept the default shown in [brackets]."
echo "    (Values already loaded from properties file will be skipped.)"
echo ""

if [[ -z "$HOSTNAME" ]]; then
    read -p "Hostname [dietpi]: " INPUT_HOSTNAME
    HOSTNAME="${INPUT_HOSTNAME:-dietpi}"
fi

if [[ -z "$TIMEZONE" ]]; then
    read -p "Timezone [America/New_York]: " INPUT_TZ
    TIMEZONE="${INPUT_TZ:-America/New_York}"
fi

if [[ -z "$LOCALE" ]]; then
    read -p "Locale [en_US.UTF-8]: " INPUT_LOCALE
    LOCALE="${INPUT_LOCALE:-en_US.UTF-8}"
fi

if [[ -z "$DIETPI_PASS" ]]; then
    read -p "DietPi global password [dietpi]: " INPUT_DIETPI_PASS
    DIETPI_PASS="${INPUT_DIETPI_PASS:-dietpi}"
fi

echo ""
echo "--- Network ---"

if [[ -z "$STATIC_IP" ]]; then
    read -p "Static IP (e.g. 192.168.1.10): " STATIC_IP
fi

DEFAULT_GATEWAY=$(echo "$STATIC_IP" | awk -F. '{print $1"."$2"."$3".1"}')

if [[ -z "$GATEWAY" ]]; then
    read -p "Gateway [$DEFAULT_GATEWAY]: " INPUT_GATEWAY
    GATEWAY="${INPUT_GATEWAY:-$DEFAULT_GATEWAY}"
fi

if [[ -z "$NETMASK" ]]; then
    read -p "Netmask [255.255.255.0]: " INPUT_MASK
    NETMASK="${INPUT_MASK:-255.255.255.0}"
fi

echo ""
echo "--- VLANs ---"

if [[ -z "$INPUT_VLAN_IPS" ]]; then
    echo "    Enter VLAN IPs or 3rd-octet IDs as a comma-separated list."
    echo "    Short IDs (e.g. 2,3,4) will be expanded using the static IP's prefix and host octet."
    read -p "VLAN IPs or 3rd-octet IDs (e.g. 2,3,4 or 192.168.2.10,192.168.3.10): " INPUT_VLAN_IPS
fi

echo ""
echo "--- NUT Client ---"

if [[ -z "$NUT_UPS_NAME" ]]; then
    read -p "UPS name (e.g. UPS2U): " NUT_UPS_NAME
fi

if [[ -z "$NUT_SERVER_IP" ]]; then
    read -p "NUT server IP: " NUT_SERVER_IP
fi

if [[ -z "$NUT_PORT" ]]; then
    read -p "NUT server port [3493]: " INPUT_NUT_PORT
    NUT_PORT="${INPUT_NUT_PORT:-3493}"
fi

if [[ -z "$NUT_USER" ]]; then
    read -p "NUT username: " NUT_USER
fi

if [[ -z "$NUT_PASS" ]]; then
    read -p "NUT password: " NUT_PASS
fi

echo ""
echo "==> All values collected. Proceeding..."
echo ""

# =============================================================================
# Expand VLAN IPs from short IDs if needed
# =============================================================================
BASE_PREFIX=$(echo "$STATIC_IP" | awk -F. '{print $1"."$2}')
BASE_HOST=$(echo "$STATIC_IP" | awk -F. '{print $4}')

IFS=',' read -ra ADDR_ARRAY <<< "$INPUT_VLAN_IPS"
VLANS_CONF=""

for entry in "${ADDR_ARRAY[@]}"; do
    clean=$(echo "$entry" | tr -d ' ')
    if [[ "$clean" =~ ^[0-9]+$ ]]; then
        clean_ip="${BASE_PREFIX}.${clean}.${BASE_HOST}"
    else
        clean_ip="$clean"
    fi
    vlan_id=$(echo "$clean_ip" | cut -d. -f3)
    VLANS_CONF+="allow-hotplug eth0.${vlan_id}
iface eth0.${vlan_id} inet static
  address ${clean_ip}
  netmask ${NETMASK}

"
done

# =============================================================================
# Configure dietpi.txt
# =============================================================================
echo "==> Configuring dietpi.txt..."

set_dietpi() {
    local key="$1"
    local val="$2"
    sed -i "s|^#\?${key}=.*|${key}=${val}|" "$DIETPI_TXT"
}

set_dietpi "AUTO_SETUP_LOCALE"               "$LOCALE"
set_dietpi "AUTO_SETUP_KEYBOARD_LAYOUT"      "us"
set_dietpi "AUTO_SETUP_TIMEZONE"             "$TIMEZONE"
set_dietpi "AUTO_SETUP_HEADLESS"             "1"
set_dietpi "SURVEY_OPTED_IN"                 "0"
set_dietpi "AUTO_SETUP_NET_HOSTNAME"         "$HOSTNAME"
set_dietpi "AUTO_SETUP_NET_ETHERNET_ENABLED" "1"
set_dietpi "AUTO_SETUP_NET_WIFI_ENABLED"     "0"
set_dietpi "AUTO_SETUP_NET_USESTATIC"        "1"
set_dietpi "AUTO_SETUP_NET_STATIC_IP"        "$STATIC_IP"
set_dietpi "AUTO_SETUP_NET_STATIC_MASK"      "$NETMASK"
set_dietpi "AUTO_SETUP_NET_STATIC_GATEWAY"   "$GATEWAY"
set_dietpi "AUTO_SETUP_NET_STATIC_DNS"       "1.1.1.1"   # temporary; first-boot script sets 127.0.0.1
set_dietpi "CONFIG_SERIAL_CONSOLE_ENABLE"    "0"
set_dietpi "CONFIG_BLUETOOTH_ENABLE"         "0"
set_dietpi "AUTO_SETUP_AUTOMATED"            "1"
set_dietpi "AUTO_SETUP_GLOBAL_PASSWORD"      "$DIETPI_PASS"
set_dietpi "AUTO_SETUP_INSTALL_SOFTWARE_ID"  "93 182"

echo "==> dietpi.txt configured."

# =============================================================================
# Write Automation_Custom_Script.sh to the boot partition
# Note: heredoc uses CUSTOMSCRIPT (unquoted) so outer variables expand into the
# generated script. Inner shell variables use \$ to survive into the target file.
# =============================================================================
echo "==> Writing Automation_Custom_Script.sh..."

cat > "$BOOT/Automation_Custom_Script.sh" << CUSTOMSCRIPT
#!/bin/bash
# =============================================================================
# Automation_Custom_Script.sh
# Runs automatically on first boot by DietPi after software installs complete.
# =============================================================================

LOG="/var/log/dietpi-automation-custom.log"
exec > >(tee -a "\$LOG") 2>&1

echo "[\$(date)] Starting custom automation script..."

# -----------------------------------------------------------------------------
# 1. Write /etc/network/interfaces
# -----------------------------------------------------------------------------
echo "[\$(date)] Writing /etc/network/interfaces..."
cat > /etc/network/interfaces << 'EOF'
# Location: /etc/network/interfaces
# Please modify network settings via: dietpi-config
# Or create your own drop-ins in: /etc/network/interfaces.d/
source interfaces.d/*
# Ethernet
allow-hotplug eth0
iface eth0 inet static
  address ${STATIC_IP}
  netmask ${NETMASK}
  gateway ${GATEWAY}
# WiFi
iface wlan0 inet dhcp
  wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
EOF

# -----------------------------------------------------------------------------
# 2. Write /etc/network/interfaces.d/vlans.conf
# -----------------------------------------------------------------------------
echo "[\$(date)] Writing vlans.conf..."
mkdir -p /etc/network/interfaces.d
printf "${VLANS_CONF}" > /etc/network/interfaces.d/vlans.conf

# -----------------------------------------------------------------------------
# 3. Purge WiFi and Bluetooth packages, disable serial console
# -----------------------------------------------------------------------------
echo "[\$(date)] Purging WiFi packages..."
apt-get purge -y wpasupplicant wireless-tools rfkill || true
apt-get autoremove -y || true

echo "[\$(date)] Purging Bluetooth packages..."
apt-get purge -y bluez bluetooth pi-bluetooth || true
apt-get autoremove -y || true

echo "[\$(date)] Disabling serial console..."
systemctl disable serial-getty@ttyS0.service || true
if grep -q "console=serial0" /boot/cmdline.txt 2>/dev/null; then
    sed -i "s|console=serial0,[0-9]* ||g" /boot/cmdline.txt
fi

# -----------------------------------------------------------------------------
# 4. Install NUT client
# -----------------------------------------------------------------------------
echo "[\$(date)] Installing nut-client..."
apt-get update -qq
apt-get install -y nut-client

# -----------------------------------------------------------------------------
# 5. Configure NUT
# -----------------------------------------------------------------------------
echo "[\$(date)] Writing /etc/nut/nut.conf..."
cat > /etc/nut/nut.conf << 'EOF'
MODE=netclient
EOF

echo "[\$(date)] Writing /etc/nut/upsmon.conf..."
cat > /etc/nut/upsmon.conf << 'EOF'
MONITOR ${NUT_UPS_NAME}@${NUT_SERVER_IP}:${NUT_PORT} 1 ${NUT_USER} ${NUT_PASS} secondary
MINSUPPLIES 1
SHUTDOWNCMD "/sbin/shutdown -h +0"
POLLFREQ 5
POLLFREQALERT 5
HOSTSYNC 15
DEADTIME 15
POWERDOWNFLAG "/etc/killpower"
OFFDURATION 30
RBWARNTIME 43200
NOCOMMWARNTIME 300
FINALDELAY 5
EOF

chmod 640 /etc/nut/upsmon.conf
chown root:nut /etc/nut/upsmon.conf

echo "[\$(date)] Creating NUT tmpfiles symlink..."
ln -sf /usr/lib/tmpfiles.d/nut-client.conf /usr/lib/tmpfiles.d/nut-common-tmpfiles.conf

systemctl enable nut-client
systemctl start nut-client

# -----------------------------------------------------------------------------
# 6. Set DNS to 127.0.0.1 now that Unbound is installed
# -----------------------------------------------------------------------------
echo "[\$(date)] Setting static DNS to 127.0.0.1..."
sed -i "s|^AUTO_SETUP_NET_STATIC_DNS=.*|AUTO_SETUP_NET_STATIC_DNS=127.0.0.1|" /boot/dietpi.txt
cat > /etc/resolv.conf << 'EOF'
nameserver 127.0.0.1
EOF
if [[ -f /etc/network/interfaces ]]; then
    sed -i "s|^#dns-nameservers.*|dns-nameservers 127.0.0.1|" /etc/network/interfaces
fi

# -----------------------------------------------------------------------------
# 7. Restore Pi-hole Teleporter backup
# -----------------------------------------------------------------------------
TELEPORTER_PATH="/boot/pihole-teleporter.zip"
if [[ -f "\$TELEPORTER_PATH" ]]; then
    echo "[\$(date)] Restoring Pi-hole Teleporter backup..."
    sleep 10
    pihole -a teleporter "\$TELEPORTER_PATH"
    if [[ \$? -eq 0 ]]; then
        echo "[\$(date)] Teleporter restore succeeded."
    else
        echo "[\$(date)] WARNING: Teleporter restore returned a non-zero exit code. Check Pi-hole status."
    fi
else
    echo "[\$(date)] WARNING: Teleporter zip not found at \$TELEPORTER_PATH — skipping restore."
fi

# -----------------------------------------------------------------------------
# 8. Configure .bashrc and write .bash_history
# -----------------------------------------------------------------------------
echo "[\$(date)] Configuring .bashrc HISTCONTROL..."
for BASHRC in /root/.bashrc /home/dietpi/.bashrc; do
    [[ -f "\$BASHRC" ]] || continue
    if grep -q "HISTCONTROL" "\$BASHRC"; then
        sed -i "s|^HISTCONTROL=.*|HISTCONTROL=ignoreboth:erasedups|" "\$BASHRC"
    else
        echo "HISTCONTROL=ignoreboth:erasedups" >> "\$BASHRC"
    fi
done

echo "[\$(date)] Writing .bash_history..."
cat > /root/.bash_history << 'EOF'
 systemctl restart nut-client
 systemctl status nut-client
 upsc ${NUT_UPS_NAME}@${NUT_SERVER_IP}:${NUT_PORT}
 pihole -up && pihole -g
EOF

echo "[\$(date)] Custom automation script complete. Rebooting..."
reboot
CUSTOMSCRIPT

chmod +x "$BOOT/Automation_Custom_Script.sh"
echo "==> Automation_Custom_Script.sh written."

# =============================================================================
# Copy teleporter zip to boot partition
# =============================================================================
echo "==> Copying teleporter zip to boot partition..."
cp "$TELEPORTER_ZIP" "$BOOT/pihole-teleporter.zip"
echo "==> Teleporter zip copied."

echo ""
echo "==> All done! SD card is ready. Eject safely before inserting into the Pi."#!/bin/bash
# =============================================================================
# prepare_sd.sh
# Run this on your host machine AFTER flashing DietPi to the SD card.
# Usage: sudo bash prepare_sd.sh <path_to_boot_partition> <path_to_teleporter_zip>
# Example: sudo bash prepare_sd.sh /media/user/bootfs ~/pihole-teleporter.zip
# =============================================================================

set -e

BOOT="${1}"
TELEPORTER_ZIP="${2}"

if [[ -z "$BOOT" || -z "$TELEPORTER_ZIP" ]]; then
    echo "Usage: sudo bash prepare_sd.sh <boot_partition_path> <teleporter_zip_path>"
    exit 1
fi

if [[ ! -d "$BOOT" ]]; then
    echo "ERROR: Boot partition not found at: $BOOT"
    exit 1
fi

if [[ ! -f "$TELEPORTER_ZIP" ]]; then
    echo "ERROR: Teleporter zip not found at: $TELEPORTER_ZIP"
    exit 1
fi

DIETPI_TXT="$BOOT/dietpi.txt"

if [[ ! -f "$DIETPI_TXT" ]]; then
    echo "ERROR: dietpi.txt not found at $DIETPI_TXT — is this the right partition?"
    exit 1
fi

# =============================================================================
# Prompt for all environment-specific values
# =============================================================================
echo ""
echo "==> Configuration"
echo "    Press Enter to accept the default shown in [brackets]."
echo ""

read -p "Hostname [dietpi]: "                         INPUT_HOSTNAME
HOSTNAME="${INPUT_HOSTNAME:-dietpi}"

read -p "Timezone [America/New_York]: "               INPUT_TZ
TIMEZONE="${INPUT_TZ:-America/New_York}"

read -p "Locale [en_US.UTF-8]: "                      INPUT_LOCALE
LOCALE="${INPUT_LOCALE:-en_US.UTF-8}"

read -p "DietPi global password [dietpi]: "           INPUT_DIETPI_PASS
DIETPI_PASS="${INPUT_DIETPI_PASS:-dietpi}"

echo ""
echo "--- Network ---"
read -p "Static IP (e.g. 192.168.1.10): "            STATIC_IP
read -p "Netmask [255.255.255.0]: "                   INPUT_MASK
NETMASK="${INPUT_MASK:-255.255.255.0}"
read -p "Gateway (e.g. 192.168.1.1): "               GATEWAY

echo ""
echo "--- VLANs ---"
echo "    Enter VLAN IPs as a comma-separated list."
echo "    The 3rd octet of each IP will automatically become the eth0.x interface ID."
read -p "VLAN IPs (e.g. 192.168.2.10, 192.168.3.10): " INPUT_VLAN_IPS

echo ""
echo "--- NUT Client ---"
read -p "UPS name (e.g. UPS2U): "                    NUT_UPS_NAME
read -p "NUT server IP: "                            NUT_SERVER_IP
read -p "NUT server port [3493]: "                   INPUT_NUT_PORT
NUT_PORT="${INPUT_NUT_PORT:-3493}"
read -p "NUT username: "                             NUT_USER
read -p "NUT password: "                             NUT_PASS

echo ""
echo "==> All values collected. Proceeding..."
echo ""

# =============================================================================
# Configure dietpi.txt
# =============================================================================
echo "==> Configuring dietpi.txt..."

set_dietpi() {
    local key="$1"
    local val="$2"
    sed -i "s|^${key}=.*|${key}=${val}|" "$DIETPI_TXT"
}

set_dietpi "AUTO_SETUP_LOCALE"               "$LOCALE"
set_dietpi "AUTO_SETUP_KEYBOARD_LAYOUT"      "us"
set_dietpi "AUTO_SETUP_TIMEZONE"             "$TIMEZONE"
set_dietpi "AUTO_SETUP_NET_HOSTNAME"         "$HOSTNAME"
set_dietpi "AUTO_SETUP_NET_ETHERNET_ENABLED" "1"
set_dietpi "AUTO_SETUP_NET_WIFI_ENABLED"     "0"
set_dietpi "AUTO_SETUP_NET_USESTATIC"        "1"
set_dietpi "AUTO_SETUP_NET_STATIC_IP"        "$STATIC_IP"
set_dietpi "AUTO_SETUP_NET_STATIC_MASK"      "$NETMASK"
set_dietpi "AUTO_SETUP_NET_STATIC_GATEWAY"   "$GATEWAY"
set_dietpi "AUTO_SETUP_NET_STATIC_DNS"       "1.1.1.1"   # temporary; first-boot script sets 127.0.0.1
set_dietpi "CONFIG_SERIAL_CONSOLE_ENABLE"    "0"
set_dietpi "CONFIG_BLUETOOTH_ENABLE"         "0"
set_dietpi "AUTO_SETUP_AUTOMATED"            "1"
set_dietpi "AUTO_SETUP_GLOBAL_PASSWORD"      "$DIETPI_PASS"
set_dietpi "AUTO_SETUP_INSTALL_SOFTWARE_ID"  "93 182"

echo "==> dietpi.txt configured."

# =============================================================================
# Build vlans.conf content from prompted VLAN IPs
# =============================================================================
VLANS_CONF=""
IFS=',' read -ra ADDR_ARRAY <<< "$INPUT_VLAN_IPS"

for ip in "${ADDR_ARRAY[@]}"; do
    clean_ip=$(echo "$ip" | tr -d ' ')
    vlan_id=$(echo "$clean_ip" | cut -d. -f3)
    
    if [[ -n "$vlan_id" ]]; then
        # Append literal block with newlines
        VLANS_CONF+="allow-hotplug eth0.${vlan_id}
iface eth0.${vlan_id} inet static
  address ${clean_ip}
  netmask ${NETMASK}

"
    fi
done

# =============================================================================
# Write Automation_Custom_Script.sh to the boot partition
# Note: heredoc uses CUSTOMSCRIPT (unquoted) so outer variables expand into the
# generated script. Inner shell variables use \$ to survive into the target file.
# =============================================================================
echo "==> Writing Automation_Custom_Script.sh..."

cat > "$BOOT/Automation_Custom_Script.sh" << CUSTOMSCRIPT
#!/bin/bash
# =============================================================================
# Automation_Custom_Script.sh
# Runs automatically on first boot by DietPi after software installs complete.
# =============================================================================

LOG="/var/log/dietpi-automation-custom.log"
exec > >(tee -a "\$LOG") 2>&1

echo "[\$(date)] Starting custom automation script..."

# -----------------------------------------------------------------------------
# 1. Write /etc/network/interfaces
# -----------------------------------------------------------------------------
echo "[\$(date)] Writing /etc/network/interfaces..."
cat > /etc/network/interfaces << 'EOF'
# Location: /etc/network/interfaces
# Please modify network settings via: dietpi-config
# Or create your own drop-ins in: /etc/network/interfaces.d/
source interfaces.d/*
# Ethernet
allow-hotplug eth0
iface eth0 inet static
  address ${STATIC_IP}
  netmask ${NETMASK}
  gateway ${GATEWAY}
# WiFi
iface wlan0 inet dhcp
  wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
EOF

# -----------------------------------------------------------------------------
# 2. Write /etc/network/interfaces.d/vlans.conf
# -----------------------------------------------------------------------------
echo "[\$(date)] Writing vlans.conf..."
mkdir -p /etc/network/interfaces.d
printf "${VLANS_CONF}" > /etc/network/interfaces.d/vlans.conf

# -----------------------------------------------------------------------------
# 3. Purge WiFi and Bluetooth packages, disable serial console
# -----------------------------------------------------------------------------
echo "[\$(date)] Purging WiFi packages..."
apt-get purge -y wpasupplicant wireless-tools rfkill || true
apt-get autoremove -y || true

echo "[\$(date)] Purging Bluetooth packages..."
apt-get purge -y bluez bluetooth pi-bluetooth || true
apt-get autoremove -y || true

echo "[\$(date)] Disabling serial console..."
systemctl disable serial-getty@ttyS0.service || true
if grep -q "console=serial0" /boot/cmdline.txt 2>/dev/null; then
    sed -i "s|console=serial0,[0-9]* ||g" /boot/cmdline.txt
fi

# -----------------------------------------------------------------------------
# 4. Install NUT client
# -----------------------------------------------------------------------------
echo "[\$(date)] Installing nut-client..."
apt-get update -qq
apt-get install -y nut-client

# -----------------------------------------------------------------------------
# 5. Configure NUT
# -----------------------------------------------------------------------------
echo "[\$(date)] Writing /etc/nut/nut.conf..."
cat > /etc/nut/nut.conf << 'EOF'
MODE=netclient
EOF

echo "[\$(date)] Writing /etc/nut/upsmon.conf..."
cat > /etc/nut/upsmon.conf << 'EOF'
MONITOR ${NUT_UPS_NAME}@${NUT_SERVER_IP}:${NUT_PORT} 1 ${NUT_USER} ${NUT_PASS} secondary
MINSUPPLIES 1
SHUTDOWNCMD "/sbin/shutdown -h +0"
POLLFREQ 5
POLLFREQALERT 5
HOSTSYNC 15
DEADTIME 15
POWERDOWNFLAG "/etc/killpower"
OFFDURATION 30
RBWARNTIME 43200
NOCOMMWARNTIME 300
FINALDELAY 5
EOF

chmod 640 /etc/nut/upsmon.conf
chown root:nut /etc/nut/upsmon.conf

echo "[\$(date)] Creating NUT tmpfiles symlink..."
ln -sf /usr/lib/tmpfiles.d/nut-client.conf /usr/lib/tmpfiles.d/nut-common-tmpfiles.conf

systemctl enable nut-client
systemctl start nut-client

# -----------------------------------------------------------------------------
# 6. Set DNS to 127.0.0.1 now that Unbound is installed
# -----------------------------------------------------------------------------
echo "[\$(date)] Setting static DNS to 127.0.0.1..."
sed -i "s|^AUTO_SETUP_NET_STATIC_DNS=.*|AUTO_SETUP_NET_STATIC_DNS=127.0.0.1|" /boot/dietpi.txt
cat > /etc/resolv.conf << 'EOF'
nameserver 127.0.0.1
EOF
if [[ -f /etc/network/interfaces ]]; then
    sed -i "s|^#dns-nameservers.*|dns-nameservers 127.0.0.1|" /etc/network/interfaces
fi

# -----------------------------------------------------------------------------
# 7. Restore Pi-hole Teleporter backup
# -----------------------------------------------------------------------------
TELEPORTER_PATH="/boot/pihole-teleporter.zip"
if [[ -f "\$TELEPORTER_PATH" ]]; then
    echo "[\$(date)] Restoring Pi-hole Teleporter backup..."
    sleep 10
    pihole -a teleporter "\$TELEPORTER_PATH"
    if [[ \$? -eq 0 ]]; then
        echo "[\$(date)] Teleporter restore succeeded."
    else
        echo "[\$(date)] WARNING: Teleporter restore returned a non-zero exit code. Check Pi-hole status."
    fi
else
    echo "[\$(date)] WARNING: Teleporter zip not found at \$TELEPORTER_PATH — skipping restore."
fi

# -----------------------------------------------------------------------------
# 8. Configure .bashrc and write .bash_history
# -----------------------------------------------------------------------------
echo "[\$(date)] Configuring .bashrc HISTCONTROL..."
for BASHRC in /root/.bashrc /home/dietpi/.bashrc; do
    [[ -f "\$BASHRC" ]] || continue
    if grep -q "HISTCONTROL" "\$BASHRC"; then
        sed -i "s|^HISTCONTROL=.*|HISTCONTROL=ignoreboth:erasedups|" "\$BASHRC"
    else
        echo "HISTCONTROL=ignoreboth:erasedups" >> "\$BASHRC"
    fi
done

echo "[\$(date)] Writing .bash_history..."
cat > /root/.bash_history << 'EOF'
sudo ln -s /usr/lib/tmpfiles.d/nut-client.conf /usr/lib/tmpfiles.d/nut-common-tmpfiles.conf
 systemctl restart nut-client
 systemctl status nut-client
 upsc ${NUT_UPS_NAME}@${NUT_SERVER_IP}:${NUT_PORT}
 pihole -up && pihole -g
EOF

echo "[\$(date)] Custom automation script complete."
CUSTOMSCRIPT

chmod +x "$BOOT/Automation_Custom_Script.sh"
echo "==> Automation_Custom_Script.sh written."

# =============================================================================
# Copy teleporter zip to boot partition
# =============================================================================
echo "==> Copying teleporter zip to boot partition..."
cp "$TELEPORTER_ZIP" "$BOOT/pihole-teleporter.zip"
echo "==> Teleporter zip copied."

echo ""
echo "==> All done! SD card is ready. Eject safely before inserting into the Pi."
