#!/bin/bash
#
# Script Name: create_lxc.sh
# Author: Alex B.
# Description: Downloads and creates new LXC container in Proxmox VE.
# Created: 2024-07-28
# Version: 1.0
# Usage: ./create_lxc.sh
#
# Script uses the pveam command-line utility to download and create lxc containers in Proxmox VE.
# https://pve.proxmox.com/pve-docs/pveam.1.html
#
#

## Variables used for container creation (# cores, network settings, etc.)
## If values are not set - script will prompt user for values during execution.
declare -A LXC_SETTINGS=(
  ["container_choice"]=""
  ["cores"]="1"
  ["description"]="lxc container"
  ["hostname"]="lxc_1"
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

## See if user wants to download new template or use one from storage:
cmd=(dialog --keep-tite --backtitle "Template Source" --title "Template Source" --menu "Select template source:" 22 76 16)
# echo "cmd: ${cmd[@]}"
count=0

options=(1 "Download new template" 2 "Use template from storage")

choice_index=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)

## Select/assign node_name variable
NODE_NAME=$(user_selection_single -b "Node Selection" -t "Please select node:" -p "pvesh get /nodes --output json" -c "node" -a "1")

## Download new template file using pveam utility
if [[ $choice_index -eq 1 ]]; then

    ## User inputs search string (ex: ubuntu)
    search_string=$(create_text_entry -t "LXC Template Search" -s "Search for available lxc templates:")

    ## See which templates are available:
    ## Create list of available templates based on search_string
    mapfile -t available_lxc_templates < <(pveam available | grep -i $search_string)
    length=${#available_lxc_templates[@]}
    ## Holds list of matching template names
    lxc_names=()
    for ((i=0; i<$length; i++)); do
    IFS='        ' read -ra split_line <<< "${available_lxc_templates[$i]}"
    if [[ -n ${split_line[1]} ]]; then
    echo "Adding ${split_line[1]} to the list"
        lxc_names+=("${split_line[1]}")
    fi
    done

    ## User selects the specific container template they want to download.
    echo "These are the container templates that match your search:"
    select lxc in "${lxc_names[@]}"; do
    echo "You selected: $lxc"

    LXC_SETTINGS['container_choice']=$lxc

    break
    done

    ## User selects storage location for template file:
    LXC_SETTINGS["template_storage"]=$(user_selection_single -b "Storage Selection" -t "Storage location for lxc template file:" -p "pvesh get /nodes/$NODE_NAME/storage --output json" -c "storage" -a "1")    

    ## Download the container template to specified storage location
    pveam download ${LXC_SETTINGS["template_storage"]} ${LXC_SETTINGS["container_choice"]}

## List available templates using pveam utility
elif [[ $choice_index -eq 2 ]]; then

    ## Please choose storage to check for vm template file:
    LXC_SETTINGS["container_choice"]=$(user_selection_single -b "LXC Selection" -t "Please choose storage to check for template file::" -p "pvesh get /nodes/$NODE_NAME/storage --output json" -c "storage" -a "1")    

    LXC_SETTINGS["container_choice"]=$(user_selection_single -b "LXC Selection" -t "Please choose template file:" -p "pvesh get /nodes/$NODE_NAME/storage/${LXC_SETTINGS['container_choice']}/content --output json" -c "volid" -a "1")

else
  echo "Invalid selection. Exiting."
  exit 1
fi

declare -p container_choice num_cores description hostname memory nameserver onboot ostemplate start vm_storage template_storage swap unprivileged timezone vm_id
## Create form to finalize specs:
# open fd
exec 3>&1

# Store data to $VALUES variable
VALUES=$(dialog --ok-label "Submit" \
    --backtitle "LXC Specifications" \
    --title "LXC Specifications" \
    --form "Please confirm:" \
15 50 0 \
    "Container choice:" 1 1 $container_choice 	1 10 10 0 \
    "Cores:"    2 1	$num_cores  	2 10 15 0 \
    "Description:"    3 1	$description  	3 10 8 0 \
    "Hostname:"    4 1	$hostname  	4 10 8 0 \
    "Memory:"    5 1	$memory  	5 10 8 0 \
    "Nameserver:"    6 1	$nameserver  	6 10 8 0 \
    "Onboot:"    7 1	$onboot  	7 10 8 0 \
    "OSTemplate:"    8 1	$ostemplate  	8 10 8 0 \
    "Start:"    9 1	$start  	9 10 8 0 \
    "VM Storage:"    10 1	$vm_storage  	10 10 8 0 \
    "Template Storage:"    11 1	$template_storage  	11 10 8 0 \
    "Swap:"    12 1	$swap  	12 10 8 0 \
    "Unprivileged:"    13 1	$unprivileged  	13 10 8 0 \
    "Timezone:"    14 1	$timezone  	14 10 8 0 \
    "VM ID:"    15 1	$vm_id  	15 10 8 0 \
2>&1 1>&3)

# close fd
exec 3>&-

## use mapfile to turn values into array
mapfile -t lxc_settings_choices <<< "$VALUES"

## Assign variable values to array
LXC_SETTINGS["container_choice"]="${lxc_settings_choices[0]}"
LXC_SETTINGS["cores"]="${lxc_settings_choices[1]}"
LXC_SETTINGS["description"]="${lxc_settings_choices[2]}"
LXC_SETTINGS["hostname"]="${lxc_settings_choices[3]}"
LXC_SETTINGS["memory"]="${lxc_settings_choices[4]}"
LXC_SETTINGS["nameserver"]="${lxc_settings_choices[5]}"
LXC_SETTINGS["onboot"]="${lxc_settings_choices[6]}"
LXC_SETTINGS["ostemplate"]="${lxc_settings_choices[7]}"
LXC_SETTINGS["start"]="${lxc_settings_choices[8]}"
LXC_SETTINGS["vm_storage"]="${lxc_settings_choices[9]}"
LXC_SETTINGS["template_storage"]="${lxc_settings_choices[10]}"
LXC_SETTINGS["swap"]="${lxc_settings_choices[11]}"
LXC_SETTINGS["unprivileged"]="${lxc_settings_choices[12]}"
LXC_SETTINGS["timezone"]="${lxc_settings_choices[13]}"
LXC_SETTINGS["vm_id"]="${lxc_settings_choices[14]}"

## Have user enter network/bridge individually:
vm_network_choice=$(user_selection_single -b "Network Selection" -t "Please select network for VM:" -p "pvesh get /nodes/$NODE_NAME/network --type any_bridge --output json" -c "iface" -a "1")
NET_ADAPTER_INFO["bridge"]=$vm_network_choice


## Create the container
## pvesh create /nodes/$NODE_NAME/lxc --vmid ${LXC_SETTINGS["vmid"]} --ostemplate "${LXC_SETTINGS["template_storage"]}:vztmpl/${LXC_SETTINGS["container_choice"]}" --hostname "${LXC_SETTINGS["hostname"]}" --cores ${LXC_SETTINGS["cores"]} --memory "${LXC_SETTINGS["memory"]}" --swap ${LXC_SETTINGS["swap"]} --net0 "name=${NET_ADAPTER_INFO["name"]},bridge=${NET_ADAPTER_INFO["bridge"]},firewall=${NET_ADAPTER_INFO["firewall"]}" --onboot ${LXC_SETTINGS["onboot"]} --start ${LXC_SETTINGS["start"]} --description ${LXC_SETTINGS["description"]} --nameserver ${LXC_SETTINGS["nameserver"]} --timezone ${LXC_SETTINGS["timezone"]} --storage ${LXC_SETTINGS["vm_storage"]}torage "${LXC_SETTINGS["vm_storage"]}"
echo "ostemplate choice: ${LXC_SETTINGS['template_storage']}:vztmpl/${LXC_SETTINGS['container_choice']}"
pvesh create /nodes/$NODE_NAME/lxc --ostemplate "${LXC_SETTINGS['template_storage']}:vztmpl/${LXC_SETTINGS['container_choice']}" --vmid "${LXC_SETTINGS["vmid"]}" --hostname "${LXC_SETTINGS["hostname"]}" --memory "${LXC_SETTINGS["memory"]}" --net0 "name=${NET_ADAPTER_INFO["name"]},bridge=${NET_ADAPTER_INFO["bridge"]},firewall=${NET_ADAPTER_INFO["firewall"]}" --description "${LXC_SETTINGS["description"]}" --storage "${LXC_SETTINGS["vm_storage"]}" --start "${LXC_SETTINGS['start']}"

dialog \
    --backtitle "Terminal Session" \
    --title "Now entering terminal session.." \
    --no-collapse \
    --msgbox "You will now enter a terminal session in the container that was created. Please set root/user passwords accordingly." 50 50

## Enter terminal session on the container
pct enter ${LXC_SETTINGS["vmid"]}
