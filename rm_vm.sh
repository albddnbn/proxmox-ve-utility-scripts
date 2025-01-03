#!/bin/bash
#
# Script Name: rm_vm.sh
# Author: Alex B.
# Description: Presents checklist of VMs and containers to user, destroys selected items.
# Date: 2024-07-28
# Usage: ./rm_vm.sh
#
# The script checks whether chosen item is a VM or container and destroys it using the appropriate command-line utility.
# Script uses the qm and pct command-line utilities to remove VMs and containers from Proxmox VE.
# 
# https://pve.proxmox.com/pve-docs/pct.1.html
# https://pve.proxmox.com/pve-docs/qm.1.html
#
# ---------------------------------------------------------------------------------------------------------------------
# To Do: combine pct/qm sections since they use similar arguments.

## Source functions from functions dir.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

for file in $(ls "$script_dir/functions/"*".sh"); do
    source "$file"
done

VMS_TO_REMOVE=$(create_checklist -b "Select VMs to remove:" --title "Select VMs to remove:" --pvesh "pvesh get /cluster/resources --type vm --noborder --output-format json" -mc "vmid" -sc "name")
dialog --clear
for single_vm in $VMS_TO_REMOVE; do

    ## this loop cycles through the VM IDs that user has chosen to delete.
    ## the id property of /cluster/resources --type vm holds whether a VM is qemu or lxc
    mapfile -t pve_api_listing <<< $(eval "pvesh get /cluster/resources --type vm --output json" | jq -r ".[] | .id" | grep "$single_vm")

    container_type=$(echo $pve_api_listing | cut -d '/' -f 1)

    if [ $container_type == "qemu" ]; then
        container_type="qm"
    elif [ $container_type == "lxc" ]; then
        container_type="pct"
    else
        echo "Unknown container type: $container_type"
    fi

    dev_status=$(eval "$container_type status $single_vm")

    if [ $dev_status == *"running"*]; then
        eval "$container_type stop $single_vm" 2>/dev/null &
        pid=$! # Process Id of the previous running command
        run_spinner $pid "Removing $container_type: $single_vm"
    fi

    eval "$container_type destroy $single_vm -purge" 2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Removing $container_type: $single_vm"

done
