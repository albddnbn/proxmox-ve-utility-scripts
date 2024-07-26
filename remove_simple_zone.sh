#!/bin/bash
## Script will remove specified simple zone, and all of it's vnet/subnet children in Proxmox VE using Proxmox API.
## Created by Alex B. / July 21, 2024

apt install jq dialog -y

source functions.sh

## Display user menu selection, if there is only one zone - menu will still be displayed
ZONE_CHOICE=$(user_selection_single -t "Select zone to remove:" -p "pvesh get /cluster/sdn/zones --type simple --noborder --output json" -c "zone" -a "0")

dialog --clear

## Creates an array of listings from the vnet API endpoint
readarray -t vnets_json_string < <(pvesh get /cluster/sdn/vnets --noborder --output-format json | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]")
## You basically end up with a numbered list, vnets_json_string[0] being the first vnet  and related information
for i in "${vnets_json_string[@]}"; do

    ## Separates the number key, from the vnet information (the value)
    IFS='=' read -r key value <<< "$i"

    ## Use jq tool to extract value for vnet and zone name
    current_vnet="$(jq -r '.vnet' <<< "$value")"
    current_vnet_zone_name="$(jq -r '.zone' <<< "$value")"
    #echo "current_vnet: $current_vnet"

    ## If current vnet in cycle's zone matches zone choice - delete the vnet and all of it's subnets.
    if [[ $current_vnet_zone_name == $ZONE_CHOICE ]]; then

        ## Get listing of subnets, take same approach
        readarray -t subnets_json_string < <(pvesh get /cluster/sdn/vnets/$current_vnet/subnets --noborder --output-format json | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]")
        for i in "${subnets_json_string[@]}"; do
            IFS='=' read -r key value <<< "$i"
            current_subnet="$(jq -r '.subnet' <<< "$value")"
            echo "current_subnet: $current_subnet"
            pvesh delete /cluster/sdn/vnets/$current_vnet/subnets/$current_subnet
        done

        ## delete the vnet
        pvesh delete /cluster/sdn/vnets/$current_vnet

    fi
done

## Delete the zone:
echo "/cluster/sdn/zones/$ZONE_CHOICE"
pvesh delete "/cluster/sdn/zones/$ZONE_CHOICE"

## Reload networking config:
pvesh set /cluster/sdn
