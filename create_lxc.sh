## Downloads chosen template to specified storage location in Proxmox VE using the pveam utility.
## Then, creates a container using the downloaded template.
## THIS IS A ROUGH SCRIPT - Some plans I already have to improve are:
## ---- 1. give user choice of downloading template or searching their storage disks
## ---- 2. add more error handling
## ---- 3. Condense code through use of functions
## Resources: https://pve.proxmox.com/pve-docs/pveam.1.html
##
## Created by: Alex B
## Date: July 23, 2024

## Variables used for container creation (# cores, network settings, etc.)
## If values are not set - script will prompt user for values during execution.
declare -A VARS=(
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

## User inputs search string (ex: ubuntu)
read -p "Search available templates (ex: ubuntu, centos): " search_string

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

  VARS['container_choice']=$lxc

  break
done

## User chooses node (if there is only one node, it's auto-selected)
mapfile -t nodes < <(pvesh ls /nodes)
length=${#nodes[@]}
if [[ $length -gt 1 ]]; then
  echo "\e[33mMultiple nodes found:\e[0m Please select the node you would like to use."
  filename_strings=()
  for ((i=0; i<$length; i++)); do
    IFS='        ' read -ra split_line <<< "${nodes[$i]}"
    filename_strings+=("${split_line[1]}")
  done
  echo "Please select your node name:"
  select NODE_NAME in "${filename_strings[@]}"; do
    if [[ -n $NODE_NAME ]]; then
      echo -e "You have selected: \e[33m$NODE_NAME\e[0m"
      break
    else
      echo "Invalid selection. Please try again."
    fi
  done
else
  IFS='        ' read -ra split_line <<< "${nodes[0]}"
  NODE_NAME="${split_line[1]}"
  echo -e "\nAuto-selected node: \e[33m$NODE_NAME\e[0m"
fi

## Create list of available storage choices for the selected node
mapfile -t storage_list < <(pvesh get /nodes/$NODE_NAME/storage -content vztmpl -enabled --noborder --output json | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]")
storage_names=()
for i in "${storage_list[@]}"; do

    ## Separates the number key, from the vnet information (the value)
    IFS='=' read -r key value <<< "$i"

    ## Use jq on the 'storage' object json string to extract the storage name.
    storage_name="$(jq -r '.storage' <<< "$value")"
    storage_names+=("$storage_name")
done

## User selects storage location for container template file
echo "Select storage location for template file:"
select STORAGE_NAME in "${storage_names[@]}"; do
if [[ -n $STORAGE_NAME ]]; then
    echo -e "You have selected: \e[33m$STORAGE_NAME\e[0m"

    VARS["template_storage"]=$STORAGE_NAME

    break
else
    echo "Invalid selection. Please try again."
fi
done

## Download the container template to specified storage location
pveam download ${VARS["template_storage"]} ${VARS["container_choice"]}

## Prompt for missing values:

## Step 1, get vm id from user:
read -p "Enter the VM ID: " vm_id
VARS["vmid"]=$vm_id

## Get hostname
read -p "Enter the hostname: " hostname
VARS["hostname"]=$hostname

## Step 2, user chooses storage location for container:
echo "Select storage location for container:"
select STORAGE_NAME in "${storage_names[@]}"; do
if [[ -n $STORAGE_NAME ]]; then
    echo -e "You have selected: \e[33m$STORAGE_NAME\e[0m"

    VARS["vm_storage"]=$STORAGE_NAME

    break
else
    echo "Invalid selection. Please try again."
fi
done

## User chooses the bridge/network for container's network adapter:
## pvesh get /nodes/$NODE_NAME/network --type any_bridge --noborder --output json | jq -r '.[] | .iface'
mapfile -t bridges < <(pvesh get /nodes/$NODE_NAME/network --type any_bridge --noborder --output json | jq -r '.[] | .iface')
echo "Select bridge for container:"
select bridge in "${bridges[@]}"; do


  echo "You selected: $bridge"

  NET_ADAPTER_INFO["bridge"]=$bridge

  break
done

## User chooses whether to start the container on boot
echo "Start container on boot?"
select yn in "Yes" "No"; do
  case $yn in
    Yes ) VARS["onboot"]=1; break;;
    No ) VARS["onboot"]=0; break;;
  esac
done

## User chooses whether to start the container immediately
# echo "Start container after creation?"
# select yn in "Yes" "No"; do
#   case $yn in
#     Yes ) VARS["start"]=1; break;;
#     No ) VARS["start"]=0; break;;
#   esac
# done

## VM starts automatically after creation - user enters terminal session using pct
VARS["start"]=1

## Create the container
## pvesh create /nodes/$NODE_NAME/lxc --vmid ${VARS["vmid"]} --ostemplate "${VARS["template_storage"]}:vztmpl/${VARS["container_choice"]}" --hostname "${VARS["hostname"]}" --cores ${VARS["cores"]} --memory "${VARS["memory"]}" --swap ${VARS["swap"]} --net0 "name=${NET_ADAPTER_INFO["name"]},bridge=${NET_ADAPTER_INFO["bridge"]},firewall=${NET_ADAPTER_INFO["firewall"]}" --onboot ${VARS["onboot"]} --start ${VARS["start"]} --description ${VARS["description"]} --nameserver ${VARS["nameserver"]} --timezone ${VARS["timezone"]} --storage ${VARS["vm_storage"]}torage "${VARS["vm_storage"]}"
echo "ostemplate choice: ${VARS['template_storage']}:vztmpl/${VARS['container_choice']}"
pvesh create /nodes/$NODE_NAME/lxc --ostemplate "${VARS['template_storage']}:vztmpl/${VARS['container_choice']}" --vmid "${VARS["vmid"]}" --hostname "${VARS["hostname"]}" --memory "${VARS["memory"]}" --net0 "name=${NET_ADAPTER_INFO["name"]},bridge=${NET_ADAPTER_INFO["bridge"]},firewall=${NET_ADAPTER_INFO["firewall"]}" --description "${VARS["description"]}" --storage "${VARS["vm_storage"]}" --start "${VARS['start']}"

echo ""
echo "YOU ARE NOW ENTERING A TERMINAL SESSION ON THE CONTAINER"
echo -e "\e[33mPLEASE SET ROOT PASSWORD using 'passwd' command\e[0m"
echo ""
echo "After you've set password, you can use 'exit' to return to proxmox host."

## Enter terminal session on the container
pct enter ${VARS["vmid"]}
