#!/bin/bash
# ** RUN AT OWN RISK - SCRIPT STILL HAS ISSUES **
# Script Name: new_dir.sh *Testing*
# Author: Alex B.
# Description: Targets specified storage device in filesystem. Initializes disk and creates single ex4 partition which is
#              mounted to the /mnt directory persistently. A new storage directory is created in Proxmox VE using the
#              pvesm command-line utility.
# Date: 2024-07-28
# Usage: ./new_dir.sh
#
# Script uses the pvesm utility to add storage directory to Proxmox VE.
# https://pve.proxmox.com/pve-docs/pvesm.1.html
#
# ---------------------------------------------------------------------------------------------------------------------
# To Do:
# - Improve script
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
    echo -e '\nCreates a new Proxmox storage directory/disk.\n'
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

## User enters name for Proxmox Directory:
PROXMOX_DIR_NAME=$(create_text_entry -t "Proxmox Directory Name" -s "Enter name for Proxmox directory (will be added to /mnt/):")

## Give user option to select storage device.
## This creates an array of all storage DISKS on system:
## disk_names=$(echo "$json_data" | jq -r '.blockdevices[] | select(.type == "disk") | .name')
json_data=$(lsblk -J)
uninitialized_disks=$(echo "$json_data" | jq -r '.blockdevices[] | select(.type == "disk") | select(.children == null) | .name')
mapfile -t disk_options_array <<<$(echo "$uninitialized_disks")

echo "options: ${disk_options_array[@]}"

cmd=(dialog --clear --backtitle "Storage selection" --title "System storage" --menu "Please select storage device. Devices in this list have no child partitions, and have not been initialized." 22 76 16)
# echo "cmd: ${cmd[@]}"
count=0

options=()
for single_option in "${disk_options_array[@]}"; do

    echo "single_option: $single_option"
    added_string="$((++count)) "$single_option""
    # matching_options+=($single_option)
    options+=($added_string)
done

length=${#disk_options_array[@]}

chosen_disk=""

if [[ ($length -gt 1) ]]; then
    choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)

    ## subtract one from final_choice to get index
    final_choice=$((choices - 1))

    ## 'return' the selected option
    chosen_disk="${disk_options_array[$final_choice]}"
else
    chosen_disk="${disk_options_array[0]}"
fi
echo "Chosen storage device: $chosen_disk"

## if a disk was chosen:
if [[ -z "$chosen_disk" ]]; then
    echo "NOTICE: No disks were found that were not already initialized and partitioned."
    exit 1
fi

##

block_device_path="/dev/$chosen_disk"
partition_path="/dev/${chosen_disk}1"

## Initialize / partition disk:
parted "$block_device_path" mklabel gpt
parted -a opt "$block_device_path" mkpart primary ext4 0% 100%

## Format as ext4:
mkfs.ext4 -L "$PROXMOX_DIR_NAME" "$partition_path"

## Create directory in /mnt for disk:
mkdir -p "/mnt/$PROXMOX_DIR_NAME"

## Mount partition to /mnt directory:
mount -o defaults "$partition_path" "/mnt/$PROXMOX_DIR_NAME"

fstab_string="LABEL=$PROXMOX_DIR_NAME /mnt/$PROXMOX_DIR_NAME ext4 defaults 0 2"

## Add to /etc/fstab:
echo "$fstab_string" >>/etc/fstab

## Add storage to Proxmox
pvesm add dir "$PROXMOX_DIR_NAME" --path "/mnt/$PROXMOX_DIR_NAME" --content rootdir,backup,iso,vztmpl,images,snippets
