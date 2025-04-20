#!/bin/bash
#
# Script Name: new_vm.sh
# Author: Alex B.
# Date: 2024-11-14
# Description: Creates new Proxmox VMs in a loop - increments given hostname by one.
# *Hoping this will just replace the new_vm script eventually..
# Usage: ./multi_new_vm.sh
# Notes:
# - Search for available VM IDs seems like it reaally could use some improvement.
#
# ---------------------------------------------------------------------------------------------------------------------
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
    echo -e '\nCreates a new Proxmox Virtual Machine.\n'
    echo -e 'Script fails if no ISOs are found in the selected storage.\n'
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

## Source functions from functions dir.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

for file in $(ls "$script_dir/functions/"*".sh"); do
    source "$file"
done

## BASIC VIRTUAL MACHINE SETTINGS:
## Starting vm id - script will start creating VMs at this id and increment upwards as available.
## Hostname prefix - prefix for VM hostnames, a number is appended. If it's a single digit, it has a 0 before it.
declare -A VM_SETTINGS=(
    ## Details for VM creation:
    ["STARTING_VM_ID"]="100"   # Ex: 101
    ["HOSTNAME_PREFIX"]="a-pc" # Ex: lab-pc-
    ["NUM_CORES"]=1            # Number of CPU cores used by VM
    ["NUM_SOCKETS"]=1          # Number of CPU sockets used by VM
    ["MEMORY"]=8192            # VM Memory in GB
    ["VM_NETWORK"]=""          # Network for VM
    ["VM_HARDDISK_SIZE"]="60"  # Ex: 60 would create a 60 GB hard disk.
    ["NUMBER_VMS"]=1           # Number of VMs to create
)

# Store data to $VALUES variable and present is as form
VALUES=$(dialog --ok-label "Submit" \
    --backtitle "Settings Verification" \
    --title "Verify Virtual Machine Settings" \
    --form "Please correct values as necessary:" \
    25 80 0 \
    "Starting VM ID:" 1 1 "${VM_SETTINGS['STARTING_VM_ID']}" 1 25 35 0 \
    "Number of VMs" 2 1 "${VM_SETTINGS['NUMBER_VMS']}" 2 25 35 0 \
    "Hostname Prefix:" 3 1 "${VM_SETTINGS['HOSTNAME_PREFIX']}" 3 25 35 0 \
    "Virtual Machine Memory:" 4 1 "${VM_SETTINGS['MEMORY']}" 4 25 35 0 \
    "Virtual Machine Cores:" 5 1 "${VM_SETTINGS['NUM_CORES']}" 5 25 35 0 \
    "Virtual Machine Sockets:" 6 1 "${VM_SETTINGS['NUM_SOCKETS']}" 6 25 35 0 \
    "Hard Disk Size:" 7 1 "${VM_SETTINGS['VM_HARDDISK_SIZE']}" 7 25 35 0 \
    3>&1 1>&2 2>&3 3>&-)

## turn $VALUES variable into an array
mapfile -t vm_setting_choices <<<"$VALUES"

## Reassign values to VM_SETTINGS array
VM_SETTINGS["STARTING_VM_ID"]="${vm_setting_choices[0]}"
VM_SETTINGS["NUMBER_VMS"]="${vm_setting_choices[1]}"
VM_SETTINGS["HOSTNAME_PREFIX"]="${vm_setting_choices[2]}"
VM_SETTINGS["MEMORY"]="${vm_setting_choices[3]}"
VM_SETTINGS["NUM_CORES"]="${vm_setting_choices[4]}"
VM_SETTINGS["NUM_SOCKETS"]="${vm_setting_choices[5]}"
VM_SETTINGS["VM_HARDDISK_SIZE"]="${vm_setting_choices[6]}"

## Select node name (node is auto-selected if there's only one)
NODE_NAME=$(user_selection_single -b "Node Selection" -t "Please select node:" -p "pvesh get /nodes --output json" -c "node" -a "1")

## Array will contain user's choices for VM storage, as well as where script will look for ISOs to attach to VM.
declare -A STORAGE_OPTIONS=(
    ["ISO_STORAGE"]="Select storage that contains ISO(s) for OS install:"
    ["VM_STORAGE"]="Select disk for VM hard disk storage:"
)

## The user is prompted to select the Windows and VirtIO isos, from the contents of STORAGE_OPTIONS['ISO_STORAGE'].
declare -A chosen_isos=(
    ["main_iso"]="VM will boot from this ISO"
    ["virtio_iso"]="Secondary ISO selection"
)

dialog --clear

########################################################################################################################
## Stage 3 - Collection of storage options and ISOs
##
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
vm_network_reply=$(user_selection_single -b "Network Selection" -t "Please select network for VMs:" -p "pvesh get /nodes/$NODE_NAME/network --type any_bridge --output json" -c "iface" -a "1")
VM_SETTINGS["VM_NETWORK"]=$vm_network_reply

## Network adapter type.
NETWORK_ADAPTER_TYPE="e1000" # Some example options include: e1000, virtio e1000e. There are likely options for Realtek and VMWare adapters as well.

## cycle through num_vms:
for i in $(seq ${VM_SETTINGS['NUMBER_VMS']}); do

    ## Does not add anything to hostname for first vm created, after that - appends a number.
    if [ $i -lt 10 ]; then
        i="0$i"
    fi
    virtual_machine_name="${VM_SETTINGS['HOSTNAME_PREFIX']}$i"

    vm_ids=$(pvesh get /cluster/resources --type vm -output json | jq -r '.[] | .vmid')

    while [[ ${vm_ids[@]} =~ "${VM_SETTINGS['STARTING_VM_ID']}" ]]; do
        echo "Setting new vm id: ${VM_SETTINGS['STARTING_VM_ID']}"
        new_vm_id=$((${VM_SETTINGS['STARTING_VM_ID']} + 1))
        VM_SETTINGS['STARTING_VM_ID']=$new_vm_id
        echo "New vm id: ${VM_SETTINGS['STARTING_VM_ID']}"
    done

    ## Creates a vm using specified ISO(s) and storage locations.
    # Reference for 'ideal' VM settings: https://davejansen.com/recommended-settings-windows-10-2016-2018-2019-vm-proxmox/
    #  -tpmstate "${STORAGE_OPTIONS['VM_STORAGE']}:4,version=v2.0,"
    pvesh create /nodes/$NODE_NAME/qemu -vmid ${VM_SETTINGS['STARTING_VM_ID']} -name "$virtual_machine_name" -storage ${STORAGE_OPTIONS['ISO_STORAGE']} \
        -memory 8192 -cpu cputype=x86-64-v2-AES -cores 4 -sockets 1 -cdrom "${chosen_isos['main_iso']}" \
        -ide1 "${chosen_isos['virtio_iso']},media=cdrom" -net0 "$NETWORK_ADAPTER_TYPE,bridge=${VM_SETTINGS['VM_NETWORK']},firewall=1" \
        -scsihw virtio-scsi-pci -bios ovmf -machine pc-q35-8.1 \
        -efidisk0 "${STORAGE_OPTIONS['VM_STORAGE']}:1" -bootdisk ide2 -ostype win11 \
        -agent 1 -virtio0 "${STORAGE_OPTIONS['VM_STORAGE']}:${VM_SETTINGS['VM_HARDDISK_SIZE']},iothread=1,format=qcow2" -boot "order=ide2;virtio0;scsi0"

done
