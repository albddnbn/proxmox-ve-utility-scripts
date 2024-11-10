#!/bin/bash
#
# Script Name: start_vms.sh
# Author: Alex B.
# Date: 2024-07-28
# Description: Starts or stops specified list of virtual machines/containers.
# Usage: ./new_vm.sh
## Source functions from functions dir.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

for file in $(ls "$script_dir/functions/"*".sh"); do
    source "$file"
done

VMS_TO_START=$(create_checklist -b "Select VMs to start:" --title "Select VMs to start:" --pvesh "pvesh get /cluster/resources --type vm --noborder --output-format json" -mc "vmid" -sc "name")
dialog --clear
for single_vm in $VMS_TO_START; do

    mapfile -t pve_api_listing <<< $(eval "pvesh get /cluster/resources --type vm --output json" | jq -r ".[] | .id" | grep "$single_vm")

    container_type=$(echo $pve_api_listing | cut -d '/' -f 1)

    if [ $container_type == "qemu" ]; then
        container_type="qm"
    elif [ $container_type == "lxc" ]; then
        container_type="pct"
    else
        echo "Unknown container type: $container_type"
    fi

    eval "$container_type start $single_vm" 2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Removing $container_type: $single_vm"
done