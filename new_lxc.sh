#!/bin/bash
#
# Script Name: create_lxc.sh
# Author: Alex B.
# Description: Downloads and creates new LXC container in Proxmox VE.
# Date: 2024-07-28
# Usage: ./create_lxc.sh
#
# Script uses the pveam command-line utility to download lxc containers in Proxmox VE.
# https://pve.proxmox.com/pve-docs/pveam.1.html
#
# ---------------------------------------------------------------------------------------------------------------------
# To Do:
# - Check on possibility of setting password more efficiently but still securely.
# - Check on container config options.


## Source functions from functions dir.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

for file in $(ls "$script_dir/functions/"*".sh"); do
    source "$file"
done

## Variables used for container creation (# cores, network settings, etc.)
## If values are not set - script will prompt user for values during execution.
declare -A LXC_SETTINGS=(
  ["container_choice"]=""
  ["cores"]="1"
  ["description"]="lxc container"
  ["hostname"]="lxc1"
  ["memory"]="2048"
  ["nameserver"]="8.8.8.8"
  ["onboot"]=0
  ["ostemplate"]=""
#   ["insecure_pw"]="Somepass1" ## The first thing to do after container creation is set a secure password.
  ["start"]=0
  ["vm_storage"]=""
  ["template_storage"]=""
  ["swap"]="512"
  ["unprivileged"]=0
  ["timezone"]="host"
  ["vm_id"]=""
)

## Container's network adapter information
declare -A NET_ADAPTER_INFO=(
    ["name"]="net0"
    ["bridge"]=""
    ["firewall"]=1
)

## User selects 1 to download new template or 2 to use template from storage:
cmd=(dialog --backtitle "Template Source" --title "Template Source" --menu "Select template source:" 22 76 16)
count=0
options=(1 "Download new template" 2 "Use template from storage")
choice_index=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)

## User chooses node name (auto-selected if there's only one node)
NODE_NAME=$(user_selection_single -b "Node Selection" -t "Please select node:" -p "pvesh get /nodes --output json" -c "node" -a "1")

########################################################################################################################
## Option 1: Download template from Proxmox VE repository
########################################################################################################################
if [[ $choice_index -eq 1 ]]; then

    ## User inputs search string (ex: ubuntu)
    search_string=$(create_text_entry -t "LXC Template Search" -s "Search for available lxc templates:")

    ## See which templates are available:
    ## Create list of available templates based on search_string
    mapfile -t available_lxc_templates < <(pveam available | grep -i $search_string)
    length=${#available_lxc_templates[@]}
    echo "available_lxc_templates: ${available_lxc_templates[@]}"
    ## Holds list of matching template names
    lxc_names=()
    for ((i=0; i<$length; i++)); do
    IFS='        ' read -ra split_line <<< "${available_lxc_templates[$i]}"
    if [[ -n ${split_line[1]} ]]; then
    echo "Adding ${split_line[1]} to the list"
        lxc_names+=("${split_line[1]}")
    fi
    done

    ## Display menu with lxc_names:
    cmd=(dialog --keep-tite --backtitle "LXC Selection" --title "LXC Selection" --menu "Select container template to download:" 22 76 16)

    count=0
    lxc_menu_options=()
    for single_option in "${lxc_names[@]}"; do
        # echo "single_option: $single_option"
        added_string="$((++count)) "$single_option""
        echo "added_string: $added_string"
        lxc_menu_options+=($added_string)
    done

    length=${#lxc_names[@]}
    if [[ ($length -gt 1) ]]; then
        final_choice=$("${cmd[@]}" "${lxc_menu_options[@]}" 2>&1 >/dev/tty)
        ## subtract one from final_choice to get index
        final_choice=$((final_choice-1))
        ## 'return' the selected option
        echo "${lxc_names[$final_choice]}"
        LXC_SETTINGS["container_choice"]="${lxc_names[$final_choice]}"
    else
        echo "$lxc_names"
        LXC_SETTINGS["container_choice"]="${lxc_names[0]}"
    fi

    ## User selects storage location for template file:
    storage_choice=$(user_selection_single -b "Storage Selection" -t "Storage location for lxc template file:" -p "pvesh get /nodes/$NODE_NAME/storage --output json" -c "storage" -a "1")    
    LXC_SETTINGS["template_storage"]=$storage_choice
    ## Download the container template to specified storage location
    echo "pveam download ${LXC_SETTINGS["template_storage"]} ${LXC_SETTINGS["container_choice"]}"
    pveam download "${LXC_SETTINGS["template_storage"]}" "${LXC_SETTINGS["container_choice"]}"

    LXC_SETTINGS["ostemplate"]="${LXC_SETTINGS['template_storage']}":vztmpl/"${LXC_SETTINGS['container_choice']}"

########################################################################################################################
## Option 2: Use template from storage
########################################################################################################################
elif [[ $choice_index -eq 2 ]]; then

    ## Please choose storage to check for vm template file:
    user_container_choice=$(user_selection_single -b "LXC Selection" -t "Please choose storage to check for template file::" -p "pvesh get /nodes/$NODE_NAME/storage --output json" -c "storage" -a "1")    
    LXC_SETTINGS["template_storage"]="${user_container_choice}"

    user_container_choice=$(user_selection_single -b "LXC Selection" -t "Please choose template file:" -p "pvesh get /nodes/$NODE_NAME/storage/$user_container_choice/content --output json" -c "volid" -a "1")
    
    LXC_SETTINGS["container_choice"]="${user_container_choice}"

    LXC_SETTINGS["ostemplate"]="${user_container_choice}"
else
  echo "Invalid selection. Exiting."
  return 1
fi


## User selects storage that will be used by container:
lxc_location=$(user_selection_single -b "Storage Selection" -t "Please select storage location for lxc image:" -p "pvesh get /nodes/$NODE_NAME/storage --output json" -c "storage" -a "1")
LXC_SETTINGS["vm_storage"]=$lxc_location

## Confirmation of container settings before creation through use of dialog form:
exec 3>&1
VALUES=$(dialog --ok-label "Submit" \
    --backtitle "Proxmox LXC Settings" \
    --title "Proxmox LXC Settings" \
    --form "Confirm container settings:" \
25 80 0 \
    "Container choice:" 1 1	"${LXC_SETTINGS['container_choice']}" 	1 20 50 0 \
    "Cores:"    2 1	"${LXC_SETTINGS['cores']}"  	2 20 50 0 \
    "Description:"    3 1	"${LXC_SETTINGS['description']}"  	3 20 50 0 \
    "Hostname:"     4 1	"${LXC_SETTINGS['hostname']}" 	4 20 50 0 \
    "Memory:"    5 1	"${LXC_SETTINGS['memory']}"  	5 20 50 0 \
    "OS Template:"    6 1	"${LXC_SETTINGS['ostemplate']}"  	6 20 100 0 \
    "VM Storage:"     7 1	"${LXC_SETTINGS['vm_storage']}" 	7 20 50 0 \
    "Template Storage:"    8 1	"${LXC_SETTINGS['template_storage']}"  	8 20 50 0 \
    "Nameserver:"    9 1	"${LXC_SETTINGS['nameserver']}"  	9 20 50 0 \
    "Onboot:"     10 1	"${LXC_SETTINGS['onboot']}" 	10 20 50 0 \
    "Start:"     11 1	"${LXC_SETTINGS['start']}" 	11 20 50 0 \
    "Swap:"    12 1	"${LXC_SETTINGS['swap']}"  	12 20 50 0 \
    "Unprivileged:"    13 1	"${LXC_SETTINGS['underprivileged']}"  	13 20 50 0 \
    "Timezone:"     14 1	"${LXC_SETTINGS['timezone']}" 	14 20 50 0 \
    "VM ID:"     15 1	"${LXC_SETTINGS['vm_id']}" 	15 20 50 0 \
2>&1 1>&3)
exec 3>&-

# ## use mapfile to turn values into array
mapfile -t lxc_settings_choices <<< "$VALUES"

# ## Assign variable values to array
LXC_SETTINGS["container_choice"]="${lxc_settings_choices[0]}"
LXC_SETTINGS["cores"]="${lxc_settings_choices[1]}"
LXC_SETTINGS["description"]="${lxc_settings_choices[2]}"
LXC_SETTINGS["hostname"]="${lxc_settings_choices[3]}"
LXC_SETTINGS["memory"]="${lxc_settings_choices[4]}"
LXC_SETTINGS["ostemplate"]="${lxc_settings_choices[5]}"
LXC_SETTINGS["vm_storage"]="${lxc_settings_choices[6]}"
LXC_SETTINGS["template_storage"]="${lxc_settings_choices[7]}"
LXC_SETTINGS["nameserver"]="${lxc_settings_choices[8]}"
LXC_SETTINGS["onboot"]="${lxc_settings_choices[9]}"
LXC_SETTINGS["start"]="${lxc_settings_choices[10]}"
LXC_SETTINGS["swap"]="${lxc_settings_choices[11]}"
LXC_SETTINGS["unprivileged"]="${lxc_settings_choices[12]}"
LXC_SETTINGS["timezone"]="${lxc_settings_choices[13]}"
LXC_SETTINGS["vm_id"]="${lxc_settings_choices[14]}"

## User chooses network/bridge to be connected to container network adapter:
vm_network_choice=$(user_selection_single -b "Network Selection" -t "Please select network for VM:" -p "pvesh get /nodes/$NODE_NAME/network --type any_bridge --output json" -c "iface" -a "1")
NET_ADAPTER_INFO["bridge"]=$vm_network_choice

## This loop ensures the VM ID is not taken.
vm_id_open="no"
while [ "$vm_id_open" == "no" ]; do
  vm_id_check=$(check_pve_item -p "pvesh get /cluster/resources --type vm --output json" -s "${LXC_SETTINGS[vm_id]}" -c "id")
  vm_ids_separated=()
  ## Separate out the ID #s using cut -d '/' -f 2
  ## the items originally look like 'qemu/101' or 'lxc/102' so we have to chop off the 'container type'
  for vm_id_string in $vm_id_check; do
    vm_ids_separated+=($(echo "$vm_id_string" | cut -d '/' -f 2))
  done;

  ## Check vm_ids_separated for exact match of VARS[vm_id]
  exact_match=$(echo "${vm_ids_separated[@]}" | grep -ow "${LXC_SETTINGS[vm_id]}")
  if [ -z "$exact_match" ]; then
    vm_id_open="yes"
  else
    ## Resource for the redirection part of the command below: https://stackoverflow.com/questions/29222633/bash-dialog-input-in-a-variable#29222709
    new_vm_id=$(dialog --inputbox "VM ID ${LXC_SETTINGS[vm_id]} is already in use. Please select a new VM ID:" 0 0 3>&1 1>&2 2>&3 3>&-)
    LXC_SETTINGS["vm_id"]=$new_vm_id
  fi
  dialog --clear
done

########################################################################################################################
## Container creation:
########################################################################################################################
pvesh create /nodes/$NODE_NAME/lxc -ostemplate "${LXC_SETTINGS['ostemplate']}" \
    -vmid "${LXC_SETTINGS['vm_id']}" -hostname "${LXC_SETTINGS['hostname']}" -memory "${LXC_SETTINGS['memory']}" \
    -net0 "name=${NET_ADAPTER_INFO['name']},bridge=${NET_ADAPTER_INFO['bridge']},firewall=${NET_ADAPTER_INFO['firewall']}" \
    -description "${LXC_SETTINGS['description']}" -storage "${LXC_SETTINGS['vm_storage']}"


## At the end of script - user is shown a notification/warning that theyll be entering the container so they can set the
## root/user passwords.
dialog \
    --backtitle "Terminal Session" \
    --title "Now entering terminal session.." \
    --no-collapse \
    --msgbox "You will now enter a terminal session in the container that was created. Please set root/user passwords accordingly." 50 50

pct start ${LXC_SETTINGS["vm_id"]}

## Enter terminal session on the container
pct enter ${LXC_SETTINGS["vm_id"]}
