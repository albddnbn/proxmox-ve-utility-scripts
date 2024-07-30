function run_spinner () {
    local pid=$1 # Process Id of the previous running command
    local spinner_message=$2
    local spin='-\|/'

    local color='\033[1;32;1;37m'
    local color_end='\033[0m'

    i=0
    while kill -0 $pid 2>/dev/null
    do
    i=$(( (i+1) %4 ))
    clear
    printf "\r${spin:$i:1} $color$spinner_message$color_end\n"
    sleep .1
    done
    # echo "/ Completed: $spinner_message"
}

## Placeholder function showing how to present a form using bash dialog.
## Source: https://bash.cyberciti.biz/guide/The_form_dialog_for_input
function present_form () {
    shell=""
    groups=""
    user=""
    home=""

    # open fd
    exec 3>&1

    # Store data to $VALUES variable
    VALUES=$(dialog --ok-label "Submit" \
        --backtitle "Linux User Managment" \
        --title "Useradd" \
        --form "Create a new user" \
    15 50 0 \
        "Username:" 1 1	"$user" 	1 10 10 0 \
        "Shell:"    2 1	"$shell"  	2 10 15 0 \
        "Group:"    3 1	"$groups"  	3 10 8 0 \
        "HOME:"     4 1	"$home" 	4 10 40 0 \
    2>&1 1>&3)

    # close fd
    exec 3>&-

    ## use mapfile to turn values into array
    mapfile -t array_items <<< "$VALUES"

    # for single_value in $VALUES; do
    #     echo "$single_value"
    # done
}