#!/bin/bash
#
# Script Name: start_vms.sh
# Author: Alex B.
# Date: 2024-11-10
# Description: Starts or stops specified list of virtual machines/containers.
# Usage: ./new_vm.sh
# Notes: Script kind of pointless but may be able to be developed into something useful.
## Source functions from functions dir.
if ! command -v dialog &>/dev/null; then
    apt install dialog -y
else
    echo "Dialog is already installed."
fi

if ! command -v jq &>/dev/null; then
    apt install jq -y
else
    echo "jq is already installed."
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

for file in $(ls "$script_dir/functions/"*".sh"); do
    source "$file"
done

VMS_TO_START=$(create_checklist -b "Select VMs to start:" --title "Select VMs to start:" --pvesh "pvesh get /cluster/resources --type vm --noborder --output-format json" -mc "vmid" -sc "name")
VMS_TO_START=${VMS_TO_START//' '/,}

dialog --clear

pvenode startall --vms "$VMS_TO_START" --force
