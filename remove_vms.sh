## Presents list of all VMs - user checks off ones to remove.
## Script really needs to grab id column from the api endpoint so we can differentiate between containers/VMs/etc.
## ^ Right now, I only know that pct destroy looks for container in nodes/NODE/lxc/VMID.conf
## qm destroy likely checks in nodes/NODE/qemu/VMID.conf
source functions.sh

VMS_TO_REMOVE=$(create_checklist -b "Select VMs to remove:" --title "Select VMs to remove:" --pvesh "pvesh get /cluster/resources --type vm --noborder --output-format json" -mc "vmid" -sc "name")
dialog --clear
for single_vm in $VMS_TO_REMOVE; do
    # echo "Removing VM: $single_vm"
    ## use pct to force shutdown the vm then destroy it:
    # pct shutdown $single_vm -forceStop 1

    ## destroy the vm
    qm destroy $single_vm -purge 2>/dev/null &
    pid=$! # Process Id of the previous running command
    run_spinner $pid "Removing VM: $single_vm"

done