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

VMS_TO_START=$(create_checklist -b "Select VMs to shutdown:" --title "Select VMs to shutdown:" --pvesh "pvesh get /cluster/resources --type vm --noborder --output-format json" -mc "vmid" -sc "name")
dialog --clear
for single_vm in $VMS_TO_START; do

    ## this loop cycles through the VM IDs that user has chosen to delete.
    ## the id property of /cluster/resources --type vm holds whether a VM is qemu or lxc
    mapfile -t pve_api_listing <<< $(eval "pvesh get /cluster/resources --type vm --output json" | jq -r ".[] | .id" | grep "$single_vm")

    container_type=$(echo $pve_api_listing | cut -d '/' -f 1)

    # read -p "Container type: $container_type"

    if [[ $container_type == "qemu" ]]; then
        ## destroy the vm
        qm shutdown $single_vm --forceStop 2>/dev/null &
        pid=$! # Process Id of the previous running command
        run_spinner $pid "Shutting down VM: $single_vm"

    elif [[ $container_type == "lxc" ]]; then
        echo "Starting LXC: $single_vm"
        pct shutdown $single_vm --forceStop 2>/dev/null &
        pid=$! # Process Id of the previous running command
        run_spinner $pid "Shutting down container: $single_vm"
    else
        echo "Unknown container type: $container_type"
    fi

done