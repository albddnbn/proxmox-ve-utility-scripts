#!/bin/bash
#
# Script Name: new_network.sh
# Author: Alex B.
# Description: Script creates simple zone, vnet, and subnet in Proxmox VE.
# Date: 2024-07-30
# Usage: ./new_network.sh
#
# ---------------------------------------------------------------------------------------------------------------------
# To Do:
# - Learn more about different networking options through Proxmox and incorporate them into script.
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
    echo -e '\nCreates a new network in Proxmox Virtual Environment.\n'
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

ZONE_NAME=""
ZONE_MTU="1460"
ZONE_TYPE="simple"
VNET_NAME=""
# VNET_ZONE=$ZONE_NAME
VNET_ZONE=""

SUBNET_CIDR="10.0.0.1/24"
SUBNET_GATEWAY="10.0.0.1"

exec 3>&1
VALUES=$(dialog --ok-label "Submit" \
    --backtitle "Virtual Network" \
    --title "Virtual Network" \
    --form "Create new virtual network" \
    15 50 0 \
    "Zone name:" 1 1 "$ZONE_NAME" 1 20 30 0 \
    "Zone MTU:" 2 1 "$ZONE_MTU" 2 20 30 0 \
    "Vnet name:" 3 1 "$VNET_NAME" 3 20 30 0 \
    "Subnet CIDR:" 4 1 "$SUBNET_CIDR" 4 20 30 0 \
    "Subnet Gateway:" 5 1 "$SUBNET_GATEWAY" 5 20 40 0 \
    2>&1 1>&3)

# close fd
exec 3>&-

## use mapfile to turn values into array
mapfile -t array_items <<<"$VALUES"

ZONE_NAME="${array_items[0]}"
ZONE_MTU="${array_items[1]}"
VNET_NAME="${array_items[2]}"
SUBNET_CIDR="${array_items[3]}"
SUBNET_GATEWAY="${array_items[4]}"
VNET_ZONE=$ZONE_NAME

## MAke sure Zone doesn't already exist:
zone_exists="yes"
while [ "$zone_exists" == "yes" ]; do
    zone_check=$(check_pve_item -p "pvesh get /cluster/sdn/zones --output json" -s "$ZONE_NAME" -c "zone")

    if [ -z "$zone_check" ]; then
        zone_exists="no"
    else
        ZONE_NAME=$(create_text_entry -t "Create Simple Zone" -s "Zone $ZONE_NAME already exists, please choose another zone name:")
        zone_exists="yes"
    fi
done

pvesh create /cluster/sdn/zones --zone $ZONE_NAME --type $ZONE_TYPE --mtu $ZONE_MTU 2>/dev/null &
pid=$! # Process Id of the previous running command
run_spinner $pid "Creating zone $ZONE_NAME..."

pvesh create /cluster/sdn/vnets --vnet "$VNET_NAME" --zone "$ZONE_NAME" 2>/dev/null &
pid=$! # Process Id of the previous running command
run_spinner $pid "Creating subnet $VNET_NAME..."

pvesh create /cluster/sdn/vnets/$VNET_NAME/subnets --subnet "$SUBNET_CIDR" -gateway "$SUBNET_GATEWAY" -snat 0 -type subnet 2>/dev/null &
pid=$! # Process Id of the previous running command
run_spinner $pid "Creating subnet $VNET_NAME..."
