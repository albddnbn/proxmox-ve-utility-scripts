## Simple text entry.
## Source: https://stackoverflow.com/questions/29222633/bash-dialog-input-in-a-variable
function create_text_entry () {
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
Usage: $(basename "${BASH_SOURCE[0]}") [-h] -p|--pvesh pvesh_cmd -s|--search search_string -c|--column column_to_grab

Check if item exists using given pvesh command, search string, and column to grab:

Available options:

-h, --help      Print this help and exit
-p, --pvesh     pvesh command, ex: pvesh get /cluster/sdn/zones --type simple --output json
-s, --param     search string, ex: "zone1"
-c, --param     column to search in, ex: zone
EOF
}

    set -Eeuo pipefail
    trap cleanup SIGINT SIGTERM ERR EXIT

    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)


    while [ "$#" -gt 0 ]; do
        case "$1" in
            -t|--title)
                title="$2"
                shift 2
                ;;
            -s|--subtext)
                subtext="$2"
                shift 2
                ;;
            *)
            echo "Unknown option: $1"
            return 1
            ;;
        esac
    done
    user_input=$(\
    dialog --clear --title "$title" \
        --inputbox "$subtext" 8 40 \
        3>&1 1>&2 2>&3 3>&- \
    )

    echo "$user_input"
}