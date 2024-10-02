## Source functions from functions dir.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

for file in $(ls "$script_dir/functions/"*".sh"); do
    source "$file"
done
## choose VM to clone
# pvesh get /cluster/resources --type vm --noborder --output-format json | jq -r '.[] | {(.vmid|tostring):(.name)}'s
#VM_TO_CLONE=$(user_selection_single -b "VM Selection" -t "Select VM to clone:" -p "pvesh get /cluster/resources --type vm --noborder --output-format json" -c "node" -a "1")
btitle="Select VM to clone"
column_to_grab="vmid"
secondary_column="name"
#pvesh_cmd="pvesh get /cluster/resources --type vm --noborder --output-format json | jq -r '.[] | {(.vmid|tostring):(.name)}'"
pvesh_cmd="pvesh get /cluster/resources --type vm --output-format json"

cmd=(dialog --title \"$btitle\" --menu \"$btitle\" 22 76 16)
# echo "cmd: ${cmd[@]}"

formatted_checklist_options=()
main_col_results=$(eval "$pvesh_cmd" | jq -r ".[] | .$column_to_grab|tostring")
mapfile -t main_results <<< "$main_col_results"
secondary_column=$(eval "$pvesh_cmd" | jq -r ".[] | .$secondary_column|tostring")
mapfile -t sec_col_results <<< "$secondary_column"


echo "main_col_results: $main_col_results"
echo "sec_col_results: ${sec_col_results[@]}"
## Some different ways to format output with jq, I'm putting them here for safekeeping:
## pvesh get /cluster/resources --type vm --output json | jq '. [] | {(.name): .vmid}'
## pvesh get /cluster/resources --type vm --output json | jq '. [] | "\(.vmid) \(.name)"'
## pvesh get /cluster/resources --type vm --output json | jq -r '. [] | "{id: \(.vmid),name: \(.name)}"'
## results=$(pvesh get /cluster/resources --type vm --output json | jq -r '. [] | "{id: \(.vmid),name: \(.name)}"')

count=0
for single_option in $main_col_results; do
    target_index=$count
    ## increment count
    count=$((count+1))
    ## Create the display_name for the option:
    display_name="$single_option ${sec_col_results[$target_index]}"
    formatted_checklist_string="$count \"$display_name\""
    echo "formatted_checklist_string: $formatted_checklist_string"
    formatted_checklist_options+=($formatted_checklist_string)
done

# echo "executing cmd: ${cmd[@]} ${formatted_checklist_options[@]}"
choices=$(eval "${cmd[@]} ${formatted_checklist_options[@]}" 2>&1 >/dev/tty)

# echo "$choices"

final_results=()
for choice in $choices; do
    ## subtract one from final_choice to get index
    final_choice=$((choice-1))
    final_results+=("${main_results[$final_choice]}")

done

echo "${final_results[@]}"
chosen_vm="${final_results[@]}"
## get chosen vm hostname - kinda repetitive this way?
chosen_vm_hostname=$(eval "$pvesh_cmd" | jq -r ".[] | select(.vmid == $chosen_vm) | .name")

## choose number of clones
NUM_CLONES=$(create_text_entry -t "Number of clones" -s "Enter number of clones to create:")

## as long as num_clones is a number - proceed:
case $NUM_CLONES in
    ''|*[!0-9]*) proceed='no' ;;
    *) proceed='yes' ;;
esac

if [ "$proceed" == "yes" ]; then

    ## get starting vm id:
    starting_vm_id=$(create_text_entry -t "Starting VM ID" -s "Enter starting VM ID for clones:")

    echo "Creating $NUM_CLONES clones from: $chosen_vm"

    mapfile -t pve_api_listing <<< $(eval "pvesh get /cluster/resources --type vm --output json" | jq -r ".[] | .id" | grep "${final_results[@]}")

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


