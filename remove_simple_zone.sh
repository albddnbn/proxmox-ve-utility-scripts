#!/bin/bash
## Script will remove specified simple zone, and all of it's vnet/subnet children in Proxmox VE using Proxmox API.
## Created by Alex B. / July 21, 2024
## Works, but terminal output is messy. Need to clean up output and add spinner for each deletion.

# apt install jq dialog -y
# set -Eeuo pipefail ## Check on this line - https://betterdev.blog/minimal-safe-bash-script-template/
## Sounded like useful concept but atm its tripping script up.

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

for file in $(ls "$script_dir/functions/"*".sh"); do
    source "$file"
done

## Display user menu selection, if there is only one zone - menu will still be displayed
# ZONE_CHOICE=$(user_selection_single -t "Select zone to remove:" -p "pvesh get /cluster/sdn/zones --type simple --output json" -c "zone" -a "0")
ZONE_CHOICES=$(create_checklist -b "Select zones to remove:" --title "Select zones to remove:" --pvesh "pvesh get /cluster/sdn/zones --type simple --output-format json" -mc "zone" -sc "type")
# dialog --clear
pvesh get /cluster/sdn/vnets --output json | jq -r '.[] | .zone'
mapfile -t ZONE_CHOICES <<< $(echo $ZONE_CHOICES | tr " " "\n" | sort -u)
# echo "ZONE_CHOICES: ${ZONE_CHOICES[@]}"
for single_zone in ${ZONE_CHOICES[@]}; do

    ## Creates an array of listings from the vnet API endpoint
    readarray -t vnets_json_string < <(pvesh get /cluster/sdn/vnets --noborder --output-format json | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]")
    
    # matching_items=$(check_pve_item -p "pvesh get /cluster/sdn/vnets --output json" -c "zone" -s "$single_zone")
    # echo "matching_items: $matching_items"
    # for single_item in $matching_items; do
    #     read -p "single_item: $single_item"
    # done
    
    ## You basically end up with a numbered list, vnets_json_string[0] being the first vnet  and related information
    for i in "${vnets_json_string[@]}"; do

        ## Separates the number key, from the vnet information (the value)
        IFS='=' read -r key value <<< "$i"

        ## Use jq tool to extract value for vnet and zone name
        current_vnet="$(jq -r '.vnet' <<< "$value")"
        current_vnet_zone_name="$(jq -r '.zone' <<< "$value")"
        #echo "current_vnet: $current_vnet"

        ## If current vnet in cycle's zone matches zone choice - delete the vnet and all of it's subnets.
        # if [[ $current_vnet_zone_name == $ZONE_CHOICE ]]; then

            ## check if current_vnet_zone_name is one of elements in ZONE_CHOICES
            #https://linuxsimply.com/bash-scripting-tutorial/conditional-statements/if-else/if-in-array/
            if [[ "${ZONE_CHOICES[@]}" =~ "$current_vnet_zone_name" ]]; then

                # echo "current_vnet_zone_name: $current_vnet_zone_name is in ZONE_CHOICES"

                ## Get listing of subnets, take same approach
                readarray -t subnets_json_string < <(pvesh get /cluster/sdn/vnets/$current_vnet/subnets --noborder --output-format json | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]")
                for i in "${subnets_json_string[@]}"; do
                    IFS='=' read -r key value <<< "$i"
                    current_subnet="$(jq -r '.subnet' <<< "$value")"
                    pvesh delete /cluster/sdn/vnets/$current_vnet/subnets/$current_subnet  2>/dev/null &
                    pid=$! # Process Id of the previous running command
                    run_spinner $pid "Reloading networking config..."
                done

                ## delete the vnet
                pvesh delete /cluster/sdn/vnets/$current_vnet 2>/dev/null &
                pid=$! # Process Id of the previous running command
                run_spinner $pid "Reloading networking config..."

            # else
            #     echo "current_vnet_zone_name: $current_vnet_zone_name is not in ZONE_CHOICES"
            fi
            
    done

    ## Delete the zone:
    pvesh delete "/cluster/sdn/zones/$single_zone"

done
if [[ -n $ZONE_CHOICES ]]; then
    # echo "Zones removed: ${ZONE_CHOICES[@]}"
    ## Reload networking config:
    pvesh set /cluster/sdn 2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Reloading networking config..."
fi
