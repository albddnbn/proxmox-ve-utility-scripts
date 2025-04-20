#!/bin/bash
#
# Script Name: stop_vms.sh
# Author: Alex B.
# Date: 2024-11-10
# Description: Attempts to 'force stop' specified list of virtual machines/containers.
# Usage: ./stop_vms.sh
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

VMS_TO_STOP=$(create_checklist -b "Select VMs to attempt to stop:" --title "Select VMs to attempt to stop:" --pvesh "pvesh get /cluster/resources --type vm --noborder --output-format json" -mc "vmid" -sc "name")
VMS_TO_STOP=${VMS_TO_STOP//' '/,}

dialog --clear

pvenode stopall --vms "$VMS_TO_STOP" --force
