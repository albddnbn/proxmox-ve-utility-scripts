#!/bin/bash
#
# Script Name: new_dc_vm.sh
# Author: Alex B.
# Date: 2024-11-10
# Description: Script creates virtual machine and corresponding SDN/virtual networking elements if specified.
#              Virtual machine will have two CDs/ISOs attached:
#                  1. Operating System ISO (Windows, Linux) - virtual machine will boot to this when started.
#                  2. Secondary ISO - such as VirtIO or other drivers.
# Usage: ./new_vm.sh
# Notes:
# - dc-vm-rules.txt - contains firewall rules for a WINDOWS DOMAIN CONTROLLER VM.
# - Virtual machine hardware settings derived from 'known good' recommendations:
#     https://4sysops.com/archives/create-a-windows-vm-in-proxmox-ve/
#     https://davejansen.com/recommended-settings-windows-10-2016-2018-2019-vm-proxmox/
#
# ---------------------------------------------------------------------------------------------------------------------
# To Do:
# - Test new firewall rules .txt
# Notes:
# - I'm not exactly sure what's going on with the alises, but it seems to work as is / except it inputs the LAN CIDR.

########################################################################################################################
## Stage 1 - Preparation
## Sourcing functions file, defining associative arrays, ensuring values are set, prompting user when necessary.
########################################################################################################################
msg() {
    echo >&2 -e "${1-}"
}

die() {
    local msg=$1
    local code=${2-1} # default exit status 1
    msg "$msg"
    exit "$code"
}

cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    # script cleanup here
}

usage() {
    # cat << EOF # remove the space between << and EOF, this is due to web plugin issue
    echo -e '\nCreates a new virtual machine.\nWindows Active Directory Domain Controller using dc-vm-rules.txt for Proxmox firewall rules.\n'
}

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

# script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

while [ "$#" -gt 0 ]; do
    case "$1" in
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
done

apt install jq dialog -y

apt install jq dialog -y

## Source functions from functions dir.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

for file in $(ls "$script_dir/functions/"*".sh"); do
    source "$file"
done

declare -A VM_SETTINGS=(
    ## Details for VM creation:
    ["VM_ID"]="110"            # Ex: 101
    ["VM_NAME"]="ad-lab-dc-vm" # Ex: lab-dc-01
    ["NUM_CORES"]=4            # Number of CPU cores used by VM
    ["NUM_SOCKETS"]=1          # Number of CPU sockets used by VM
    ["MEMORY"]=16384           # VM Memory in GB
    ["VM_NETWORK"]=""
    ["FIREWALL_RULES_FILE"]="dc-vm-rules.txt"

    ## 'Aliases' used for firewall rules/elsewhere in Proxmox OS
    ["MACHINE_ALIAS"]="addcvm"                       # Ex: labdc
    ["MACHINE_ALIAS_COMMENT"]="Domain controller VM" # Ex: Domain Controller
    ["MACHINE_CIDR"]=""                              # Ex: 10.0.0.2/32
    ## Used to replace string with MACHINE_ALIAS in firewall rules file:
    ["MACHINE_REPLACEMENT_STR"]="((\$MACHINE_ALIAS\$))" # Must change corresponding value in firewall rules file if changed.

    ["LAN_ALIAS"]="addclan"             # Ex: lablan
    ["LAN_COMMENT"]="AD Lab Domain LAN" # Ex: Domain LAN
    ["LAN_CIDR"]=""                     # Ex: 10.0.0.1/24
    ## Used to replace string with lan_alias in firewall rules file:
    ["LAN_REPLACEMENT_STR"]="((\$LAN_ALIAS\$))" # Must change corresponding value in firewall rules file if changed.
    ["VM_HARDDISK_SIZE"]="80"                   # Ex: 60 would create a 60 GB hard disk.

    ["VM_DATA_LOCATION"]=""
)

# make sure VM ID is avaailable
vm_ids=$(pvesh get /cluster/resources --type vm -output json | jq -r '.[] | .vmid')

while [[ ${vm_ids[@]} =~ "${VM_SETTINGS['VM_ID']}" ]]; do
    # new_vm_id=$((${VM_SETTINGS['VM_ID']} + 1))
    # VM_SETTINGS['VM_ID']=$new_vm_id
    VM_SETTINGS['VM_ID']=$((${VM_SETTINGS['VM_ID']} + 1))
done

## Confirm settings necessary for VM creation (barring network)
VALUES=$(dialog --ok-label "Submit" \
    --backtitle "Settings Verification" \
    --title "Verify Virtual Machine Settings" \
    --form "Please correct values as necessary:" \
    25 80 0 \
    "Virtual Machine ID:" 1 1 "${VM_SETTINGS['VM_ID']}" 1 25 35 0 \
    "Virtual Machine Name:" 2 1 "${VM_SETTINGS['VM_NAME']}" 2 25 35 0 \
    "Virtual Machine Memory:" 3 1 "${VM_SETTINGS['MEMORY']}" 3 25 35 0 \
    "Virtual Machine Cores:" 4 1 "${VM_SETTINGS['NUM_CORES']}" 4 25 35 0 \
    "Virtual Machine Sockets:" 5 1 "${VM_SETTINGS['NUM_SOCKETS']}" 5 25 35 0 \
    "Hard Disk Size:" 6 1 "${VM_SETTINGS['VM_HARDDISK_SIZE']}" 6 25 35 0 \
    3>&1 1>&2 2>&3 3>&-)

mapfile -t vm_setting_choices <<<"$VALUES"

## Reassign values to VM_SETTINGS array
VM_SETTINGS["VM_ID"]="${vm_setting_choices[0]}"
VM_SETTINGS["VM_NAME"]="${vm_setting_choices[1]}"
VM_SETTINGS["MEMORY"]="${vm_setting_choices[2]}"
VM_SETTINGS["NUM_CORES"]="${vm_setting_choices[3]}"
VM_SETTINGS["NUM_SOCKETS"]="${vm_setting_choices[4]}"
VM_SETTINGS["VM_HARDDISK_SIZE"]="${vm_setting_choices[5]}"

NODE_NAME=$(user_selection_single -b "Node Selection" -t "Please select node:" -p "pvesh get /nodes --output json" -c "node" -a "1")

## Let user select the Windows/VirtIO isos
## The user is prompted to select the Windows and VirtIO isos, from the contents of STORAGE_OPTIONS['ISO_STORAGE'].
declare -A chosen_isos=(
    ["main_iso"]="Select location of Windows Server iso:"
    ["virtio_iso"]="Select location of VirtIO iso:"
)

## User is prompted to select Windows and VirtIO isos
for var in "${!chosen_isos[@]}"; do
    ## Select storage, then have user select iso
    selected_storage=$(user_selection_single -b "Storage Selection" -t "${chosen_isos[$var]}" -p "pvesh get /nodes/$NODE_NAME/storage --output json" -c "storage" -a "1")
    chosen_isos[$var]=$(user_selection_single -b "ISO Selection" -t "${chosen_isos[$var]}" -p "pvesh get /nodes/$NODE_NAME/storage/$selected_storage/content --content iso --output json" -c "volid" -a "1")
done

VM_SETTINGS["VM_DATA_LOCATION"]=$(user_selection_single -b "Storage Selection" -t "Select storage for VM hard disk:" -p "pvesh get /nodes/$NODE_NAME/storage --output json" -c "storage" -a "1")

declare -A SDN_SETTINGS=(
    ## Virtual networking:
    ["ZONE_NAME"]=""    # Ex: testzone
    ["ZONE_COMMENT"]="" # Ex: This is a test zone comment.
    ["VNET_NAME"]=""    # Ex: testvnet
    ["VNET_ALIAS"]=""   # Ex: testvnet
    ["VNET_SUBNET"]=""  # Ex: 10.0.0.0/24
    ["VNET_GATEWAY"]="" # Ex: 10.0.0.1
)

## Virtual Zone/Network creation:
## Confirm settings necessary for VM creation (barring network)
ZONEVALUES=$(dialog --ok-label "Submit" \
    --backtitle "Settings Confirmation" \
    --title "Verify Proxmox SDN Zone Settings" \
    --form "Choose cancel to skip virtual network creation:" \
    25 80 0 \
    "Zone Name (<= 8 chars):" 1 1 "${SDN_SETTINGS['ZONE_NAME']}" 1 25 35 0 \
    "Zone Comment:" 2 1 "${SDN_SETTINGS['ZONE_COMMENT']}" 2 25 35 0 \
    "Vnet Name (<= 8 chars):" 3 1 "${SDN_SETTINGS['VNET_NAME']}" 3 25 35 0 \
    "Vnet Alias (<= 8 chars):" 4 1 "${SDN_SETTINGS['VNET_ALIAS']}" 4 25 35 0 \
    "Vnet Subnet w/CIDR" 5 1 "${SDN_SETTINGS['VNET_SUBNET']}" 5 25 35 0 \
    "Vnet Gateway:" 6 1 "${SDN_SETTINGS['VNET_GATEWAY']}" 6 25 35 0 \
    3>&1 1>&2 2>&3 3>&-)

if [ -n "$ZONEVALUES" ]; then
    # ## turn $VALUES variable into an array
    mapfile -t zone_setting_choices <<<"$ZONEVALUES"

    SDN_SETTINGS["ZONE_NAME"]="${zone_setting_choices[0]}"
    SDN_SETTINGS["ZONE_COMMENT"]="${zone_setting_choices[1]}"
    SDN_SETTINGS["VNET_NAME"]="${zone_setting_choices[2]}"
    SDN_SETTINGS["VNET_ALIAS"]="${zone_setting_choices[3]}"
    SDN_SETTINGS["VNET_SUBNET"]="${zone_setting_choices[4]}"
    SDN_SETTINGS["VNET_GATEWAY"]="${zone_setting_choices[5]}"

    ## Spinner shows some kind of progress next to each SDN API call
    pvesh create /cluster/sdn/zones --type simple --zone "${SDN_SETTINGS['ZONE_NAME']}" --mtu 1460 2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Creating zone: ${SDN_SETTINGS['ZONE_NAME']}"

    ## Virtual Network Creation:
    ## VNET w/SUBNET
    pvesh create /cluster/sdn/vnets --vnet "${SDN_SETTINGS['VNET_NAME']}" -alias "${SDN_SETTINGS['VNET_ALIAS']}" -zone "${SDN_SETTINGS['ZONE_NAME']}" 2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Creating VNET: ${SDN_SETTINGS['VNET_NAME']}"

    pvesh create /cluster/sdn/vnets/${SDN_SETTINGS['VNET_NAME']}/subnets --subnet "${SDN_SETTINGS['VNET_SUBNET']}" -gateway ${SDN_SETTINGS['VNET_GATEWAY']} -snat 0 -type subnet 2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Creating VNET SUBNET: ${SDN_SETTINGS['VNET_SUBNET']}"

    pvesh set /cluster/sdn 2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Reloading Network Config SDN"
fi

## VM and Network alias confirmation:
VALUES=$(dialog --ok-label "Submit" \
    --backtitle "Virtual Network" \
    --title "Verify Network Alias creations" \
    --form "Please choose cancel to skip alias creations:" \
    25 80 0 \
    "VM Alias (<= 8 chars):" 1 1 "${VM_SETTINGS['MACHINE_ALIAS']}" 1 25 35 0 \
    "VM IP Addr (CIDR):" 2 1 "${VM_SETTINGS['MACHINE_CIDR']}" 2 25 35 0 \
    "VM Alias Comment:" 3 1 "${VM_SETTINGS['MACHINE_ALIAS_COMMENT']}" 3 25 35 0 \
    "Virtual LAN Alias:" 4 1 "${VM_SETTINGS['LAN_ALIAS']}" 4 25 35 0 \
    "Virtual LAN CIDR:" 5 1 "${SDN_SETTINGS['VNET_SUBNET']}" 5 25 35 0 \
    "Virtual LAN Comment:" 6 1 "${VM_SETTINGS['LAN_COMMENT']}" 6 25 35 0 \
    3>&1 1>&2 2>&3 3>&-)

if [ -n "$VALUES" ]; then
    ## turn $VALUES variable into an array
    mapfile -t vm_setting_choices <<<"$VALUES"

    ## Reassign values to VM_SETTINGS array
    VM_SETTINGS["MACHINE_ALIAS"]="${vm_setting_choices[0]}"
    VM_SETTINGS["MACHINE_CIDR"]="${vm_setting_choices[1]}"
    VM_SETTINGS["MACHINE_ALIAS_COMMENT"]="${vm_setting_choices[2]}"
    VM_SETTINGS["LAN_ALIAS"]="${vm_setting_choices[3]}"
    VM_SETTINGS["LAN_CIDR"]="${vm_setting_choices[4]}"
    VM_SETTINGS["LAN_COMMENT"]="${vm_setting_choices[5]}"

    pvesh create /cluster/firewall/aliases --name "${VM_SETTINGS['MACHINE_ALIAS']}" -comment "${VM_SETTINGS['MACHINE_ALIAS_COMMENT']}" -cidr "${VM_SETTINGS['MACHINE_CIDR']}" 2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Creating alias: ${VM_SETTINGS['MACHINE_ALIAS']}"

    pvesh create /cluster/firewall/aliases --name "${VM_SETTINGS['LAN_ALIAS']}" -comment "${VM_SETTINGS['LAN_COMMENT']}" -cidr "${SDN_SETTINGS['VNET_SUBNET']}" 2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Creating alias: ${VM_SETTINGS['LAN_ALIAS']}"

fi

## Have user enter network/bridge individually:
vm_network_reply=$(user_selection_single -b "Network Selection" -t "Please select network for VM:" -p "pvesh get /nodes/$NODE_NAME/network --type any_bridge --output json" -c "iface" -a "1")
VM_SETTINGS["VM_NETWORK"]=$vm_network_reply

## Network adapter type.
NETWORK_ADAPTER_TYPE="e1000" # Some example options include: e1000, virtio e1000e. There are likely options for Realtek and VMWare adapters as well.

pvesh create /nodes/$NODE_NAME/qemu -vmid ${VM_SETTINGS['VM_ID']} -name "${VM_SETTINGS['VM_NAME']}" -storage ${VM_SETTINGS["VM_DATA_LOCATION"]} \
    -memory 8192 -cpu cputype=x86-64-v2-AES -cores 4 -sockets 1 -cdrom "${chosen_isos['main_iso']}" \
    -ide1 "${chosen_isos['virtio_iso']},media=cdrom" -net0 "$NETWORK_ADAPTER_TYPE,bridge=${VM_SETTINGS['VM_NETWORK']},firewall=1" \
    -scsihw virtio-scsi-pci -bios ovmf -machine pc-q35-8.1 -tpmstate "${VM_SETTINGS["VM_DATA_LOCATION"]}:4,version=v2.0," \
    -efidisk0 "${VM_SETTINGS["VM_DATA_LOCATION"]}:1,format=qcow2" -bootdisk ide2 -ostype win11 \
    -agent 1 -virtio0 "${VM_SETTINGS["VM_DATA_LOCATION"]}:${VM_SETTINGS['VM_HARDDISK_SIZE']},format=qcow2,iothread=1" -boot "order=ide2;virtio0" 2>/dev/null &
pid=$! # Process Id of the previous running command
run_spinner $pid "Creating VM: ${VM_SETTINGS['VM_NAME']}"

clear

echo "Replacing ${VM_SETTINGS['MACHINE_REPLACEMENT_STR']} with ${VM_SETTINGS['MACHINE_ALIAS']} in ${VM_SETTINGS['FIREWALL_RULES_FILE']}."

## Using the original firewall rules file, a new firewall rules file is generated in /etc/pve/firewall/ directory
## using the VMs ID number and inserting the domain controller's alias. .bak is appended to filename.
while read -r line; do
    echo "${line//${VM_SETTINGS['MACHINE_REPLACEMENT_STR']}/${VM_SETTINGS['MACHINE_ALIAS']}}" >>/etc/pve/firewall/${VM_SETTINGS['VM_ID']}.fw.bak
done <"${VM_SETTINGS['FIREWALL_RULES_FILE']}"

## Alias is created at the datacenter for the Domain/LAN network:
echo "Replacing ${VM_SETTINGS['LAN_REPLACEMENT_STR']} with ${VM_SETTINGS['LAN_ALIAS']} in ${VM_SETTINGS['FIREWALL_RULES_FILE']}."

## Using the backup file created earlier, the LAN alias is inserted into the firewall rules file.
while read -r line; do
    echo "${line//${VM_SETTINGS['LAN_REPLACEMENT_STR']}/${VM_SETTINGS['LAN_ALIAS']}}" >>/etc/pve/firewall/${VM_SETTINGS['VM_ID']}.fw
done </etc/pve/firewall/${VM_SETTINGS['VM_ID']}.fw.bak

echo "Removing backup file."
rm /etc/pve/firewall/${VM_SETTINGS['VM_ID']}.fw.bak
