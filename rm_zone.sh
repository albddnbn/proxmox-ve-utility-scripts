#!/bin/bash
#
# Script Name: rm_zone.sh
# Author: Alex B.
# Description: Script will present checklist of zones, deletes chosen zones and their contents (subnets/vnets).
# Date: 2024-07-30
# Usage: ./rm_zone.sh
#
# ---------------------------------------------------------------------------------------------------------------------
# To Do:
# - clean up output
# - improve output
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
    echo -e '\nPresents list of available zones/virtual bridges/networks.\nAttempts to remove selected ones, including any contents.\n'
}

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

# script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

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

## Source functions from functions dir.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

for file in $(ls "$script_dir/functions/"*".sh"); do
    source "$file"
done

## Display user menu selection, if there is only one zone - menu will still be displayed
# ZONE_CHOICE=$(user_selection_single -t "Select zone to remove:" -p "pvesh get /cluster/sdn/zones --type simple --output json" -c "zone" -a "0")
ZONE_CHOICES=$(create_checklist -b "Select zones to remove:" --title "Select zones to remove:" --pvesh "pvesh get /cluster/sdn/zones --type simple --output-format json" -mc "zone" -sc "type")
# dialog --clear
pvesh get /cluster/sdn/vnets --output json | jq -r '.[] | .zone'
mapfile -t ZONE_CHOICES <<<$(echo $ZONE_CHOICES | tr " " "\n" | sort -u)
for single_zone in ${ZONE_CHOICES[@]}; do

    ## Creates an array of listings from the vnet API endpoint
    readarray -t vnets_json_string < <(pvesh get /cluster/sdn/vnets --noborder --output-format json | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]")

    ## You basically end up with a numbered list, vnets_json_string[0] being the first vnet  and related information
    for i in "${vnets_json_string[@]}"; do

        ## Separates the number key, from the vnet information (the value)
        IFS='=' read -r key value <<<"$i"

        ## Use jq tool to extract value for vnet and zone name
        current_vnet="$(jq -r '.vnet' <<<"$value")"
        current_vnet_zone_name="$(jq -r '.zone' <<<"$value")"

        ## check if current_vnet_zone_name is one of elements in ZONE_CHOICES
        #https://linuxsimply.com/bash-scripting-tutorial/conditional-statements/if-else/if-in-array/
        if [[ "${ZONE_CHOICES[@]}" =~ "$current_vnet_zone_name" ]]; then

            # echo "current_vnet_zone_name: $current_vnet_zone_name is in ZONE_CHOICES"

            ## Get listing of subnets, take same approach
            readarray -t subnets_json_string < <(pvesh get /cluster/sdn/vnets/$current_vnet/subnets --noborder --output-format json | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]")
            for i in "${subnets_json_string[@]}"; do
                IFS='=' read -r key value <<<"$i"
                current_subnet="$(jq -r '.subnet' <<<"$value")"
                pvesh delete /cluster/sdn/vnets/$current_vnet/subnets/$current_subnet 2>/dev/null &
                pid=$! # Process Id of the previous running command
                run_spinner $pid "Reloading networking config..."
            done

            ## delete the vnet
            pvesh delete /cluster/sdn/vnets/$current_vnet 2>/dev/null &
            pid=$! # Process Id of the previous running command
            run_spinner $pid "Reloading networking config..."
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
