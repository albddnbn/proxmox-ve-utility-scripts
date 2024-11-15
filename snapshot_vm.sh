#!/bin/bash
#
# Script Name: new_vm.sh
# Author: Alex B.
# Date: 2024-07-28
# Description: Creates a basic Proxmox VM with option for two attached isos. Boots from ide2, and offers menu to join VM
#              to chosen network.
# Usage: ./new_vm.sh
# Notes:
# - Virtual machine hardware settings derived from 'known good' recommendations:
#     https://4sysops.com/archives/create-a-windows-vm-in-proxmox-ve/
#     https://davejansen.com/recommended-settings-windows-10-2016-2018-2019-vm-proxmox/
#
# ---------------------------------------------------------------------------------------------------------------------
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
    printf '%s\n' 'Creates a new Proxmox Virtual Machine, that has snapshot functionality.\n\n'
}

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

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
########################################################################################################################
## Stage 1 - Preparation
## Sourcing functions file, defining associative arrays, ensuring values are set, prompting user when necessary.
########################################################################################################################

## Source functions from functions dir.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

for file in $(ls "$script_dir/functions/"*".sh"); do
    source "$file"
done

declare -A VM_SETTINGS=(
    ## Details for VM creation:
    ["VM_ID"]="303"           # Ex: 101
    ["VM_NAME"]="lab-pc-02"   # Ex: lab-dc-01
    ["NUM_CORES"]=1           # Number of CPU cores used by VM
    ["NUM_SOCKETS"]=1         # Number of CPU sockets used by VM
    ["MEMORY"]=8192           # VM Memory in GB
    ["VM_NETWORK"]=""         # Network for VM
    ["VM_HARDDISK_SIZE"]="60" # Ex: 60 would create a 60 GB hard disk.
)

# Store data to $VALUES variable
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

## turn $VALUES variable into an array
mapfile -t vm_setting_choices <<<"$VALUES"

## Reassign values to VM_SETTINGS array
VM_SETTINGS["VM_ID"]="${vm_setting_choices[0]}"
VM_SETTINGS["VM_NAME"]="${vm_setting_choices[1]}"
VM_SETTINGS["MEMORY"]="${vm_setting_choices[2]}"
VM_SETTINGS["NUM_CORES"]="${vm_setting_choices[3]}"
VM_SETTINGS["NUM_SOCKETS"]="${vm_setting_choices[4]}"
VM_SETTINGS["VM_HARDDISK_SIZE"]="${vm_setting_choices[5]}"

## Select node name (node is auto-selected if there's only one)
NODE_NAME=$(user_selection_single -b "Node Selection" -t "Please select node:" -p "pvesh get /nodes --output json" -c "node" -a "1")

## Array will contain user's choices for VM storage, as well as where script will look for ISOs to attach to VM.
declare -A STORAGE_OPTIONS=(
    ["ISO_STORAGE"]="Select storage that contains Windows/VirtIO ISOs:"
    ["VM_STORAGE"]="Select disk for VM hard disk storage:"
)

## The user is prompted to select the Windows and VirtIO isos, from the contents of STORAGE_OPTIONS['ISO_STORAGE'].
declare -A chosen_isos=(
    ["main_iso"]="Operating System ISO selection:"
    ["virtio_iso"]="VirtIO/Secondary ISO Selection:"
)

dialog --clear

########################################################################################################################
## Stage 2 - Confirmation & Error checking
## Ensure VM ID is unique, confirm script settings with user.
########################################################################################################################
## Check if the VM ID already exists:
vm_id_open="no"
while [ "$vm_id_open" == "no" ]; do
    vm_id_check=$(check_pve_item -p "pvesh get /cluster/resources --type vm --output json" -s "${VM_SETTINGS[VM_ID]}" -c "id")
    vm_ids_separated=()
    ## Separate out the ID #s using cut -d '/' -f 2
    ## the items originally look like 'qemu/101' or 'lxc/102' so we have to chop off the 'container type'
    for vm_id_string in $vm_id_check; do
        vm_ids_separated+=($(echo "$vm_id_string" | cut -d '/' -f 2))
    done

    ## Check vm_ids_separated for exact match of VARS[VM_ID]
    exact_match=$(echo "${vm_ids_separated[@]}" | grep -ow "${VM_SETTINGS[VM_ID]}")
    if [ -z "$exact_match" ]; then
        vm_id_open="yes"
    else
        ## Resource for the redirection part of the command below: https://stackoverflow.com/questions/29222633/bash-dialog-input-in-a-variable#29222709
        new_vm_id=$(dialog --inputbox "VM ID ${VM_SETTINGS[VM_ID]} is already in use. Please select a new VM ID:" 0 0 3>&1 1>&2 2>&3 3>&-)
        VM_SETTINGS["VM_ID"]=$new_vm_id
    fi

    dialog --clear
done
########################################################################################################################
## Stage 3 - Collection of storage options and ISOs
## Storage locations include:
## - ISO_STORAGE: Storage location for Windows and VirtIO ISOs
## - VM_STORAGE: Storage location for VM hard disk
## User is prompted to select TWO ISOs.
## - main_iso: Windows ISO
## - virtio_iso: VirtIO ISO
########################################################################################################################

## Prompt user for STORAGE_OPTIONS values
for var in "${!STORAGE_OPTIONS[@]}"; do
    STORAGE_OPTIONS[$var]=$(user_selection_single -b "Storage Selection" -t "${STORAGE_OPTIONS[$var]}" -p "pvesh get /nodes/$NODE_NAME/storage --output json" -c "storage" -a "1")
done

## User is prompted to select Windows and VirtIO isos
for var in "${!chosen_isos[@]}"; do
    chosen_isos[$var]=$(user_selection_single -b "ISO Selection" -t "${chosen_isos[$var]}" -p "pvesh get /nodes/$NODE_NAME/storage/${STORAGE_OPTIONS['ISO_STORAGE']}/content --content iso --output json" -c "volid" -a "1")
done

########################################################################################################################
## Stage 4 - VM Creation and Joining to network
########################################################################################################################
## Have user enter network/bridge individually:
vm_network_reply=$(user_selection_single -b "Network Selection" -t "Please select network for VM:" -p "pvesh get /nodes/$NODE_NAME/network --type any_bridge --output json" -c "iface" -a "1")
VM_SETTINGS["VM_NETWORK"]=$vm_network_reply

## Network adapter type.
NETWORK_ADAPTER_TYPE="e1000" # Some example options include: e1000, virtio e1000e. There are likely options for Realtek and VMWare adapters as well.

## Creates a vm using specified ISO(s) and storage locations.
# Reference for 'ideal' VM settings: https://davejansen.com/recommended-settings-windows-10-2016-2018-2019-vm-proxmox/
pvesh create /nodes/$NODE_NAME/qemu -vmid ${VM_SETTINGS['VM_ID']} -name "${VM_SETTINGS['VM_NAME']}" -storage ${STORAGE_OPTIONS['ISO_STORAGE']} \
    -memory 8192 -cpu x86-64-v2-AES -cores 4 -sockets 1 -cdrom "${chosen_isos['main_iso']}" \
    -ide1 "${chosen_isos['virtio_iso']},media=cdrom" -net0 "$NETWORK_ADAPTER_TYPE,bridge=${VM_SETTINGS['VM_NETWORK']},firewall=1" \
    -scsihw virtio-scsi-pci -bios ovmf -machine q35 \
    -efidisk0 "${STORAGE_OPTIONS['VM_STORAGE']}:1,format=qcow2" -bootdisk ide2 -ostype win10 -numa 0 \
    -agent 1 -virtio0 "${STORAGE_OPTIONS['VM_STORAGE']}:${VM_SETTINGS['VM_HARDDISK_SIZE']},iothread=1,format=qcow2" -boot "order=ide2;virtio0"
# -tpmstate "${STORAGE_OPTIONS['VM_STORAGE']}:4,version=v2.0,"
# ostype - l26 = linux kernel 6
# ostype - win10
