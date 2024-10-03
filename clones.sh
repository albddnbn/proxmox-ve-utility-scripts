#!/bin/bash
#
# Script Name: clones.sh
# Author: Alex B.
# Description: Clones specified VM/Container X number of times. User specifies 'starting' VM ID, which is incremented
#              upwards by 1 for each clone. This number is also appended to the vm name of the newly created clone.
# Date: 2024-10-02
# Usage: ./clones.sh
#
# Script uses the qm/pct clone commands. Untested for pct at this point.
#
# ----------------------------------------------------------------------------------------------------------------------

## Source functions from functions dir.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

for file in $(ls "$script_dir/functions/"*".sh"); do
    source "$file"
done

## User chooses VM/container to clone
menu_title="Select VM to clone" # title of the dialog menu
main_col="vmid" # main column, used in display AND as identifying column for VM/containers.
display_col="name" # used for display purposes - it's easier to identify vm/containers when you have both ID/name
pvesh_cmd="pvesh get /cluster/resources --type vm --output-format json"

cmd=(dialog --title \"$menu_title\" --menu \"$menu_title\" 22 76 16) # cmd that generates menu in terminal

## For display purposes, a formatted options list is created, each item formatted like this: 'VM_ID VM_NAME'
formatted_menu_options=()
main_col_results=$(eval "$pvesh_cmd" | jq -r ".[] | .$main_col|tostring")
mapfile -t main_results <<< "$main_col_results"

display_col=$(eval "$pvesh_cmd" | jq -r ".[] | .$display_col|tostring")
mapfile -t sec_col_results <<< "$display_col"

count=0
for single_option in $main_col_results; do
    target_index=$count
    ## increment count
    count=$((count+1))
    ## Create the display_name for the option:
    display_name="$single_option ${sec_col_results[$target_index]}"
    formatted_checklist_string="$count \"$display_name\""
    echo "formatted_checklist_string: $formatted_checklist_string"
    formatted_menu_options+=($formatted_checklist_string)
done

## 'choices' will amount to a single VM/container ID, chosen by user
choices=$(eval "${cmd[@]} ${formatted_menu_options[@]}" 2>&1 >/dev/tty)
choice_index=$((choices-1))
chosen_vm="${main_results[$choice_index]}"
## get chosen vm hostname - kinda repetitive this way?
chosen_vm_hostname=$(eval "$pvesh_cmd" | jq -r ".[] | select(.vmid == $chosen_vm) | .name")

## choose number of clones
NUM_CLONES=$(create_text_entry -t "Number of clones" -s "Enter number of clones to create:")

## as long as num_clones is a number - proceed:
## Resource: https://stackoverflow.com/questions/806906/how-do-i-test-if-a-variable-is-a-number-in-bash#3951175
case $NUM_CLONES in
    ''|*[!0-9]*) proceed='no' ;;
    *) proceed='yes' ;;
esac

if [ "$proceed" == "yes" ]; then

    ## get starting vm id:
    starting_vm_id=$(create_text_entry -t "Starting VM ID" -s "Enter starting VM ID for clones:")

    echo "Creating $NUM_CLONES clones from: $chosen_vm"

    mapfile -t pve_api_listing <<< $(eval "pvesh get /cluster/resources --type vm --output json" | jq -r ".[] | .id" | grep "$chosen_vm")

    container_type=$(echo $pve_api_listing | cut -d '/' -f 1)

    for i in $(seq $NUM_CLONES); do

        clone_name="${chosen_vm_hostname}-${i}"

        vm_id_open="no"
        while [ "$vm_id_open" == "no" ]; do
            vm_id_check=$(check_pve_item -p "pvesh get /cluster/resources --type vm --output json" -s "$starting_vm_id" -c "id")
            vm_ids_separated=()
            ## Separate out the ID #s using cut -d '/' -f 2
            ## the items originally look like 'qemu/101' or 'lxc/102' so we have to chop off the 'container type'
            for vm_id_string in $vm_id_check; do
                vm_ids_separated+=($(echo "$vm_id_string" | cut -d '/' -f 2))
            done;

            ## Check vm_ids_separated for exact match of VARS[VM_ID]
            exact_match=$(echo "${vm_ids_separated[@]}" | grep -ow "$starting_vm_id")
            if [ -z "$exact_match" ]; then
                vm_id_open="yes"
            else
                ## Resource for the redirection part of the command below: https://stackoverflow.com/questions/29222633/bash-dialog-input-in-a-variable#29222709
                echo "Setting new vm id: $starting_vm_id"
                new_vm_id=$((starting_vm_id + 1))
                starting_vm_id=$new_vm_id
                echo "New vm id: $starting_vm_id"
            fi

            dialog --clear
        done


        if [[ $container_type == "qemu" ]]; then
            ## destroy the vm
            qm clone $chosen_vm $starting_vm_id --name $clone_name
            #2>/dev/null &
            # pid=$! # Process Id of the previous running command
            # run_spinner $pid "Cloning VM: $chosen_vm"

        elif [[ $container_type == "lxc" ]]; then
            echo "Cloning LXC: $chosen_vm"
            pct clone $chosen_vm 
            #-force -purge 2>/dev/null &
            # pid=$! # Process Id of the previous running command
            # run_spinner $pid "Cloning VM: $chosen_vm"
        else
            echo "Unknown container type: $container_type"
        fi


    done
else
    echo "Invalid entry. Please enter a number."
fi


