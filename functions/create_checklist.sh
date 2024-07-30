## Creates a checklist using dialog command.
## Allows for submission of two column names, in cases where one would not be descriptive enough when displayed.
## For ex: when displaying a checklist to delete virtual machines from a Proxmox cluster, the VM's ID is required
##         for use with related command line utilities. However, displaying a checklist with only the VM ID would not 
##         allow the user to make an informed choice. The secondary column in this case would be the VMs name.
## Returns chosen items from the main/first column at the moment.
function create_checklist () {

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
cat << EOF # remove the space between << and EOF, this is due to web plugin issue
Usage: $(basename "${BASH_SOURCE[0]}") [-h] -b|--backtitle back_title -t|--title menu_title -p|--pvesh pvesh_cmd -mc|--main_column column_to_grab -sc|--second_column secondary_column

Check if item exists using given pvesh command, search string, and column to grab:

Available options:

-h, --help      Print this help and exit
-b, --backtitle Backtitle of the dialog
-t, --title     Title of the dialog
-p, --pvesh     pvesh command, ex: pvesh get /cluster/sdn/zones --type simple --output json
-mc, --main_column Main column to grab, ex: zone
-sc, --second_column Secondary column to grab, ex: name
EOF
}
    set -Eeuo pipefail
    trap cleanup SIGINT SIGTERM ERR EXIT

    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)


    while [ "$#" -gt 0 ]; do
        case "$1" in
            -b|--backtitle)
                back_title="$2"
                shift 2
                ;;
            -t|--title)
                menu_title="$2"
                shift 2
                ;;
            -p|--pvesh)
                pvesh_cmd="$2"
                shift 2
                ;;
            -mc|--main_column)
                column_to_grab="$2"
                shift 2
                ;;
            -sc|--second_column)
                secondary_column="$2"
                shift 2
                ;;
            *)
            echo "Unknown option: $1"
            return 1
            ;;
        esac
    done

    cmd=(dialog --clear --separate-output --checklist \"$menu_title\" 22 76 16)
    # echo "cmd: ${cmd[@]}"

    formatted_checklist_options=()
    main_col_results=$(eval "$pvesh_cmd" | jq -r ".[] | .$column_to_grab")
    mapfile -t main_results <<< "$main_col_results"
    secondary_column=$(eval "$pvesh_cmd" | jq -r ".[] | .$secondary_column")
    mapfile -t sec_col_results <<< "$secondary_column"


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
        formatted_checklist_string="$count \"$display_name\" off"
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
}