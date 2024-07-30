#!/bin/bash
# Script Name: create_network.sh
# Author: Alex B.
# Date: 2024-07-29
# Description: Script creates simple zone, vnet, and subnet in Proxmox VE.
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

for file in $(ls "$script_dir/functions/"*".sh"); do
    source "$file"
done

## ZONE_NAME=$(create_text_entry -t "Create Simple Zone" -s "Enter zone name:")
ZONE_NAME=""
ZONE_MTU="1460"
ZONE_TYPE="simple"


## VNET_NAME=$(create_text_entry -t "Create Simple Subnet" -s "Enter subnet name:")
VNET_NAME=""
# VNET_ZONE=$ZONE_NAME
VNET_ZONE=""

SUBNET_CIDR="10.0.0.1/24"
SUBNET_GATEWAY="10.0.0.1"

# open fd
exec 3>&1

# Store data to $VALUES variable
VALUES=$(dialog --ok-label "Submit" \
    --backtitle "Linux User Managment" \
    --title "Useradd" \
    --form "Create a new user" \
15 50 0 \
    "Zone name:" 1 1	"$ZONE_NAME" 	1 10 30 0 \
    "Zone MTU:"    2 1	"$ZONE_MTU"  	2 10 30 0 \
    "Vnet name:"    3 1	"$VNET_NAME"  	3 10 30 0 \
    "Subnet CIDR:"    4 1	"$SUBNET_CIDR"  	4 10 30 0 \
    "Subnet Gateway:"     5 1	"$SUBNET_GATEWAY" 	5 10 40 0 \
2>&1 1>&3)

# close fd
exec 3>&-

## use mapfile to turn values into array
mapfile -t array_items <<< "$VALUES"

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

pvesh create /cluster/sdn/vnets/$VNET_NAME/subnets --subnet "$SUBNET_CIDR" -gateway "$SUBNET_GATEWAY" -snat 0 -type subnet   2>/dev/null &
pid=$! # Process Id of the previous running command
run_spinner $pid "Creating subnet $VNET_NAME..."
