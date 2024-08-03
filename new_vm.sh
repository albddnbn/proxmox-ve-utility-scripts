#!/bin/bash
#
# Script Name: new_vm.sh
# Author: Alex B.
# Date: 2024-07-28
# Description: Script creates virtual machine and corresponding SDN/virtual networking elements if specified.
#              Virtual machine will have two CDs/ISOs attached:
#                  1. Operating System ISO (Windows, Linux) - virtual machine will boot to this when started.
#                  2. Secondary ISO - such as VirtIO or other drivers.
# Usage: ./new_vm.sh
# Notes:
# - dc-vm-rules.txt - contains firewall rules for a WINDOWS DOMAIN CONTROLLER VM.
# - Virtual machine hardware settings derived from 'known good' recommendations:
#     https://4sysops.com/archives/create-a-windows-vm-in-proxmox-ve/
#     https://davejansen.com/recommended-settings-windows-10-2016-2018-2019-vm-proxmox/
#
# ---------------------------------------------------------------------------------------------------------------------
# To Do:
# - Look into cloud-init or other options for efficiently configuring VMs.
# - Create firewall rules files for other situations (windows client, basic linux server, etc.) 

########################################################################################################################
## Stage 1 - Preparation
## Sourcing functions file, defining associative arrays, ensuring values are set, prompting user when necessary.
########################################################################################################################

## Source functions from functions dir.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

for file in $(ls "$script_dir/functions/"*".sh"); do
    source "$file"
done

declare -A VM_SETTINGS=(
  ## Details for VM creation:
  ["VM_ID"]="303"                                      # Ex: 101
  ["VM_NAME"]="lab-pc-02"                            # Ex: lab-dc-01
  ["NUM_CORES"]=1                                      # Number of CPU cores used by VM                       
  ["NUM_SOCKETS"]=1                                    # Number of CPU sockets used by VM
  ["MEMORY"]=8192                                     # VM Memory in GB
  ["VM_NETWORK"]=""                                     
  ["FIREWALL_RULES_FILE"]="dc-vm-rules.txt"

  ## 'Aliases' used for firewall rules/elsewhere in Proxmox OS
  ["MACHINE_ALIAS"]="pc1"                                 # Ex: labdc
  ["MACHINE_ALIAS_COMMENT"]="Domain controller"            # Ex: Domain Controller
  ["MACHINE_CIDR"]="10.0.0.3/32"                                  # Ex: 10.0.0.2/32
  ## Used to replace string with MACHINE_ALIAS in firewall rules file:
  ["MACHINE_REPLACEMENT_STR"]="((\$MACHINE_ALIAS\$))"  # Must change corresponding value in firewall rules file if changed.

  ["LAN_ALIAS"]="winlan1"                              # Ex: lablan
  ["LAN_COMMENT"]="Domain LAN"                         # Ex: Domain LAN
  ["LAN_CIDR"]="10.0.0.1/24"                          # Ex: 10.0.0.1/24
  ## Used to replace string with lan_alias in firewall rules file:
  ["LAN_REPLACEMENT_STR"]="((\$LAN_ALIAS\$))"          # Must change corresponding value in firewall rules file if changed.
  ["VM_HARDDISK_SIZE"]="60"                            # Ex: 60 would create a 60 GB hard disk.
)

# Store data to $VALUES variable
VALUES=$(dialog --ok-label "Submit" \
	  --backtitle "Settings Verification" \
	  --title "Verify Virtual Machine Settings" \
	  --form "Please correct values as necessary:" \
25 80 0 \
	"Virtual Machine ID:"       1  1 	"${VM_SETTINGS['VM_ID']}" 	            1  25 35 0 \
	"Virtual Machine Name:"     2  1	"${VM_SETTINGS['VM_NAME']}" 	          2  25 35 0 \
  "Virtual Machine Memory:"   3  1	"${VM_SETTINGS['MEMORY']}" 	            3  25 35 0 \
  "Virtual Machine Cores:"    4  1	"${VM_SETTINGS['NUM_CORES']}" 	        4  25 35 0 \
  "Virtual Machine Sockets:"  5  1	"${VM_SETTINGS['NUM_SOCKETS']}" 	      5  25 35 0 \
	"Hard Disk Size:"           6  1	"${VM_SETTINGS['VM_HARDDISK_SIZE']}"  	6  25 35 0 \
	"Virtual Machine CIDR:"     7  1	"${VM_SETTINGS['MACHINE_CIDR']}"  	    7  25 35 0 \
	"Virtual Machine Alias:"    8  1	"${VM_SETTINGS['MACHINE_ALIAS']}"  	    8  25 35 0 \
	"Alias Comment:"            9  1	"${VM_SETTINGS['MACHINE_ALIAS_COMMENT']}"  	9  25 35 0 \
	"LAN CIDR:"                 10 1	"${VM_SETTINGS['LAN_CIDR']}" 	          10 25 35 0 \
  "LAN Alias:"                11 1	"${VM_SETTINGS['LAN_ALIAS']}" 	        11 25 35 0 \
	"LAN Comment:"              12 1	"${VM_SETTINGS['LAN_COMMENT']}" 	      12 25 35 0 \
3>&1 1>&2 2>&3 3>&-)

## turn $VALUES variable into an array
mapfile -t vm_setting_choices <<< "$VALUES"

## Reassign values to VM_SETTINGS array
VM_SETTINGS["VM_ID"]="${vm_setting_choices[0]}"
VM_SETTINGS["VM_NAME"]="${vm_setting_choices[1]}"
VM_SETTINGS["MEMORY"]="${vm_setting_choices[2]}"
VM_SETTINGS["NUM_CORES"]="${vm_setting_choices[3]}"
VM_SETTINGS["NUM_SOCKETS"]="${vm_setting_choices[4]}"
VM_SETTINGS["VM_HARDDISK_SIZE"]="${vm_setting_choices[5]}"
VM_SETTINGS["MACHINE_CIDR"]="${vm_setting_choices[6]}"
VM_SETTINGS["MACHINE_ALIAS"]="${vm_setting_choices[7]}"
VM_SETTINGS["MACHINE_ALIAS_COMMENT"]="${vm_setting_choices[8]}"
VM_SETTINGS["LAN_CIDR"]="${vm_setting_choices[9]}"
VM_SETTINGS["LAN_ALIAS"]="${vm_setting_choices[10]}"
VM_SETTINGS["LAN_COMMENT"]="${vm_setting_choices[11]}"

## Get VM_NETWORK individually with text entry:
# vm_network_reply=$(create_text_entry -t "Network Interface" -s "Enter network that will be used with VM nw interface:")
# VM_SETTINGS["VM_NETWORK"]="$vm_network_reply"
## Select node name (node is auto-selected if there's only one)
NODE_NAME=$(user_selection_single -b "Node Selection" -t "Please select node:" -p "pvesh get /nodes --output json" -c "node" -a "1")

declare -A SDN_SETTINGS=(
  ## Virtual networking:
  ["ZONE_NAME"]="ADLAB"                                     # Ex: testzone
  ["ZONE_COMMENT"]="Test zone 1"                                  # Ex: This is a test zone comment.
  ["VNET_NAME"]="adnet"                                     # Ex: testvnet
  ["VNET_ALIAS"]="adnet"                                    # Ex: testvnet
  ["VNET_SUBNET"]="10.0.0.1/24"                                   # Ex: 10.0.0.0/24
  ["VNET_GATEWAY"]="10.0.0.1"                                  # Ex: 10.0.0.1
)

## Array will contain user's choices for VM storage, as well as where script will look for ISOs to attach to VM.
declare -A STORAGE_OPTIONS=(
  ["ISO_STORAGE"]="Select storage that contains Windows/VirtIO ISOs:"
  ["VM_STORAGE"]="Select disk for VM hard disk storage:"
)

## The user is prompted to select the Windows and VirtIO isos, from the contents of STORAGE_OPTIONS['ISO_STORAGE'].
declare -A chosen_isos=(
  ["main_iso"]="Operating System ISO selection:"
  ["virtio_iso"]="VirtIO/Secondary ISO Selection:"
)

dialog --clear


## Secondary check to make sure VM setting variables are filled out.
# Loop through the VARS array, prompt user for any missing values.
# for var in "${!VM_SETTINGS[@]}"; do
#   if [[ -z "${VM_SETTINGS[$var]}" ]]; then

#     ## VM NETWORK doesn't have to be filled in yet:
#     if [ "$var" == "VM_NETWORK" ]; then
#       continue
#     fi
#     read -p "Enter a value for ${var}: " value
#   fi
# #   ## Strip whitespace from value, if it exists.
# #   ## if var doesn't end with _COMMENT, strip whitespace from value.
# #   if [[ $var != *_COMMENT ]]; then
# #   VM_SETTINGS[$var]="$(echo -e "${value}" | tr -d '[:space:]')"
# #   else
# #   VM_SETTINGS[$var]="${value:-}"
# #   fi
# done

########################################################################################################################
## Stage 2 - Confirmation & Error checking
## Ensure VM ID is unique, confirm script settings with user.
########################################################################################################################
## Check if the VM ID already exists:
vm_id_open="no"
while [ "$vm_id_open" == "no" ]; do
  vm_id_check=$(check_pve_item -p "pvesh get /cluster/resources --type vm --output json" -s "${VM_SETTINGS[VM_ID]}" -c "id")
  vm_ids_separated=()
  ## Separate out the ID #s using cut -d '/' -f 2
  ## the items originally look like 'qemu/101' or 'lxc/102' so we have to chop off the 'container type'
  for vm_id_string in $vm_id_check; do
    vm_ids_separated+=($(echo "$vm_id_string" | cut -d '/' -f 2))
  done;

  ## Check vm_ids_separated for exact match of VARS[VM_ID]
  exact_match=$(echo "${vm_ids_separated[@]}" | grep -ow "${VM_SETTINGS[VM_ID]}")
  if [ -z "$exact_match" ]; then
    vm_id_open="yes"
  else
    ## Resource for the redirection part of the command below: https://stackoverflow.com/questions/29222633/bash-dialog-input-in-a-variable#29222709
    new_vm_id=$(dialog --inputbox "VM ID ${VM_SETTINGS[VM_ID]} is already in use. Please select a new VM ID:" 0 0 3>&1 1>&2 2>&3 3>&-)
    VM_SETTINGS["VM_ID"]=$new_vm_id
  fi

  dialog --clear
done
########################################################################################################################
## Stage 3 - Collection of storage options and ISOs
## Storage locations include:
## - ISO_STORAGE: Storage location for Windows and VirtIO ISOs
## - VM_STORAGE: Storage location for VM hard disk
## User is prompted to select TWO ISOs.
## - main_iso: Windows ISO
## - virtio_iso: VirtIO ISO
########################################################################################################################

## Prompt user for STORAGE_OPTIONS values
for var in "${!STORAGE_OPTIONS[@]}"; do
  STORAGE_OPTIONS[$var]=$(user_selection_single -b "Storage Selection" -t "${STORAGE_OPTIONS[$var]}" -p "pvesh get /nodes/$NODE_NAME/storage --output json" -c "storage" -a "1")
done;

## User is prompted to select Windows and VirtIO isos
for var in "${!chosen_isos[@]}"; do
  chosen_isos[$var]=$(user_selection_single -b "ISO Selection" -t "${chosen_isos[$var]}" -p "pvesh get /nodes/$NODE_NAME/storage/${STORAGE_OPTIONS['ISO_STORAGE']}/content --content iso --output json" -c "volid" -a "1")
done;

########################################################################################################################
## Stage 4 - Virtual Network Creation
## If user wants to create zone, vnet, and subnet, script will create them here.
########################################################################################################################
msg=$(cat <<EOF
Create corresponding SDN elements for virtual machine?
(Zone, Vnet, and Subnet)
EOF
)

dialog --title "Create virtual network?" --yesno "$msg" 0 0
dialog_response=$?

dialog --clear

if [ "$dialog_response" == "0" ]; then
    exec 3>&1

    ZONEVALUES=$(dialog --ok-label "Submit" \
        --backtitle "Settings Confirmation" \
        --title "Verify Proxmox SDN Zone Settings" \
        --form "Please correct values as necessary:" \
    25 80 0 \
      "Zone Name:"     1  1 "${SDN_SETTINGS['ZONE_NAME']}" 	   1  25 35 0 \
      "Zone Comment:"  2  1	"${SDN_SETTINGS['ZONE_COMMENT']}"  2  25 35 0 \
      "Vnet Name:"     3  1	"${SDN_SETTINGS['VNET_NAME']}" 	   3  25 35 0 \
      "Vnet Alias:"    4  1	"${SDN_SETTINGS['VNET_ALIAS']}" 	 4  25 35 0 \
      "Vnet Subnet"    5  1	"${SDN_SETTINGS['VNET_SUBNET']}" 	 5  25 35 0 \
      "Vnet Gateway:"  6  1	"${SDN_SETTINGS['VNET_GATEWAY']}"  6  25 35 0 \
      2>&1 1>&3)

    exec 3>&-

    # ## turn $VALUES variable into an array
    mapfile -t zone_setting_choices <<< "$ZONEVALUES"

    SDN_SETTINGS["ZONE_NAME"]="${zone_setting_choices[0]}"
    SDN_SETTINGS["ZONE_COMMENT"]="${zone_setting_choices[1]}"
    SDN_SETTINGS["VNET_NAME"]="${zone_setting_choices[2]}"
    SDN_SETTINGS["VNET_ALIAS"]="${zone_setting_choices[3]}"
    SDN_SETTINGS["VNET_SUBNET"]="${zone_setting_choices[4]}"
    SDN_SETTINGS["VNET_GATEWAY"]="${zone_setting_choices[5]}"

    ## Secondary check to make sure SDN setting variables are filled out.
    # Loop through the SDN_SETTINGS array, prompt user for any missing values.
    for var in "${!SDN_SETTINGS[@]}"; do
        if [[ -z "${SDN_SETTINGS[$var]}" ]]; then
            # I think this is unnecessary
            read -p "Enter a value for ${var}: " value
        fi

        ## Is it necessary to strip whitespace values from zone/vnet/etc. names?

    done

    ## Spinner shows some kind of progress next to each SDN API call
    pvesh create /cluster/sdn/zones --type simple --zone "${SDN_SETTINGS['ZONE_NAME']}" --mtu 1460 2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Creating zone: ${SDN_SETTINGS['ZONE_NAME']}"

    ## Virtual Network Creation:
    ## VNET w/SUBNET
    pvesh create /cluster/sdn/vnets --vnet "${SDN_SETTINGS['VNET_NAME']}" -alias "${SDN_SETTINGS['VNET_ALIAS']}" -zone "${SDN_SETTINGS['ZONE_NAME']}"  2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Creating VNET: ${SDN_SETTINGS['VNET_NAME']}"

    pvesh create /cluster/sdn/vnets/${SDN_SETTINGS['VNET_NAME']}/subnets --subnet "${SDN_SETTINGS['VNET_SUBNET']}" -gateway ${SDN_SETTINGS['VNET_GATEWAY']} -snat 0 -type subnet   2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Creating VNET SUBNET: ${SDN_SETTINGS['VNET_SUBNET']}"

    pvesh set /cluster/sdn   2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Reloading Network Config SDN"

fi

## Have user enter network/bridge individually:
vm_network_reply=$(user_selection_single -b "Network Selection" -t "Please select network for VM:" -p "pvesh get /nodes/$NODE_NAME/network --type any_bridge --output json" -c "iface" -a "1")
VM_SETTINGS["VM_NETWORK"]=$vm_network_reply

## Network adapter type.
NETWORK_ADAPTER_TYPE="e1000" # Some example options include: e1000, virtio e1000e. There are likely options for Realtek and VMWare adapters as well.

## Creates a vm using specified ISO(s) and storage locations.
# Reference for 'ideal' VM settings: https://davejansen.com/recommended-settings-windows-10-2016-2018-2019-vm-proxmox/
pvesh create /nodes/$NODE_NAME/qemu -vmid ${VM_SETTINGS['VM_ID']} -name "${VM_SETTINGS['VM_NAME']}" -storage ${STORAGE_OPTIONS['ISO_STORAGE']} \
      -memory 8192 -cpu cputype=x86-64-v2-AES -cores 2 -sockets 2 -cdrom "${chosen_isos['main_iso']}" \
      -ide1 "${chosen_isos['virtio_iso']},media=cdrom" -net0 "$NETWORK_ADAPTER_TYPE,bridge=${VM_SETTINGS['VM_NETWORK']},firewall=1" \
      -scsihw virtio-scsi-pci -bios ovmf -machine pc-q35-8.1 -tpmstate "${STORAGE_OPTIONS['VM_STORAGE']}:4,version=v2.0," \
      -efidisk0 "${STORAGE_OPTIONS['VM_STORAGE']}:1" -bootdisk ide2 -ostype win11 \
      -agent 1 -virtio0 "${STORAGE_OPTIONS['VM_STORAGE']}:${VM_SETTINGS['VM_HARDDISK_SIZE']},iothread=1,format=qcow2" -boot "order=ide2;virtio0;scsi0" 2>/dev/null &
pid=$! # Process Id of the previous running command
run_spinner $pid "Creating VM: ${VM_SETTINGS['VM_NAME']}"

clear
## FIREWALL RULES FOR VM (/etc/pve/firewall)
## Alias is created at the datacenter level for domain controller VM
msg=$(cat <<EOF
Attempt to assign firewall rules for domain controller VM and create network aliases?
EOF
)

dialog --title "Firewall rules" --yesno "$msg" 0 0
dialog_response=$?

dialog --clear

if [ "$dialog_response" == "0" ]; then

    ## Check if aliases already exist.
    # alias_keys=('MACHINE_ALIAS')
    # for alias_key_name in "${alias_keys[@]}"; do
    #     alias_open="no"
    #     while [ "$alias_open" == "no" ]; do
    #     alias_check=$(check_pve_item -p "pvesh get /cluster/firewall/aliases --output json" -s "${VM_SETTINGS[$alias_key_name]}" -c "name")

    #     if [ -z "$alias_check" ]; then
    #         alias_open="yes"
    #     else
    #         ## Resource for the redirection part of the command below: https://stackoverflow.com/questions/29222633/bash-dialog-input-in-a-variable#29222709
    #         new_alias=$(dialog --inputbox "Alias ${VM_SETTINGS[$alias_key_name]} already in use. Please select another." 0 0 3>&1 1>&2 2>&3 3>&-)
    #         VM_SETTINGS[$alias_key_name]=$new_alias
    #     fi
    #     dialog --clear
    #     done
    # done

    # alias_keys=('LAN_ALIAS')
    # for alias_key_name in "${alias_keys[@]}"; do
    #     alias_open="no"
    #     while [ "$alias_open" == "no" ]; do
    #     alias_check=$(check_pve_item -p "pvesh get /cluster/firewall/aliases --output json" -s "${SDN_SETTINGS[$alias_key_name]}" -c "name")

    #     if [ -z "$alias_check" ]; then
    #         alias_open="yes"
    #     else
    #         ## Resource for the redirection part of the command below: https://stackoverflow.com/questions/29222633/bash-dialog-input-in-a-variable#29222709
    #         new_alias=$(dialog --inputbox "Alias ${SDN_SETTINGS[$alias_key_name]} already in use. Please select another." 0 0 3>&1 1>&2 2>&3 3>&-)
    #         SDN_SETTINGS[$alias_key_name]=$new_alias
    #     fi
    #     dialog --clear
    #     done
    # done



    pvesh create /cluster/firewall/aliases --name "${VM_SETTINGS['MACHINE_ALIAS']}" -comment "${VM_SETTINGS['MACHINE_ALIAS_COMMENT']}" -cidr "${VM_SETTINGS['MACHINE_CIDR']}"  2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Creating alias: ${VM_SETTINGS['MACHINE_ALIAS']}"

    echo "Replacing ${VM_SETTINGS['MACHINE_REPLACEMENT_STR']} with ${VM_SETTINGS['MACHINE_ALIAS']} in ${VM_SETTINGS['FIREWALL_RULES_FILE']}."

    ## Using the original firewall rules file, a new firewall rules file is generated in /etc/pve/firewall/ directory
    ## using the VMs ID number and inserting the domain controller's alias. .bak is appended to filename.
    while read -r line; do
    echo "${line//${VM_SETTINGS['MACHINE_REPLACEMENT_STR']}/${VM_SETTINGS['MACHINE_ALIAS']}}" >> /etc/pve/firewall/${VM_SETTINGS['VM_ID']}.fw.bak
    done < "${VM_SETTINGS['FIREWALL_RULES_FILE']}"

    ## Alias is created at the datacenter for the Domain/LAN network:
    pvesh create /cluster/firewall/aliases --name "${VM_SETTINGS['LAN_ALIAS']}" -comment "${VM_SETTINGS['LAN_COMMENT']}" -cidr "${VM_SETTINGS['LAN_CIDR']}"  2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Creating alias: ${VM_SETTINGS['LAN_ALIAS']}"

    echo "Replacing ${VM_SETTINGS['LAN_REPLACEMENT_STR']} with ${VM_SETTINGS['LAN_ALIAS']} in ${VM_SETTINGS['FIREWALL_RULES_FILE']}."

    ## Using the backup file created earlier, the LAN alias is inserted into the firewall rules file.
    while read -r line; do
    echo "${line//${VM_SETTINGS['LAN_REPLACEMENT_STR']}/${VM_SETTINGS['LAN_ALIAS']}}" >> /etc/pve/firewall/${VM_SETTINGS['VM_ID']}.fw
    done < /etc/pve/firewall/${VM_SETTINGS['VM_ID']}.fw.bak

    echo "Removing backup file."
    rm /etc/pve/firewall/${VM_SETTINGS['VM_ID']}.fw.bak

fi
