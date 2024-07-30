## Check if item exists using given pvesh command, search string, and column to grab:
# Ex: check_pve_item -p "pvesh get /cluster/resources --type vm --output json" -s "test" -c "name"
function check_pve_item () {
    set -Eeuo pipefail
    trap cleanup SIGINT SIGTERM ERR EXIT

    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

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

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                return 0
                ;;
            -p|--pvesh)
                pvesh_cmd="$2"
                shift 2
                ;;
            -s|--search)
                search_string="$2"
                shift 2
                ;;
            -c|--column)
                column_to_grab="$2"
                shift 2
                ;;
            *)
            echo "Unknown option: $1"
            return 1
            ;;
        esac
    done

    ## Source files in the functions directory:
    source "$script_dir/*.sh"
    
    ## Get listing from api endpoint:
    mapfile -t pve_api_listing <<< $(eval "$pvesh_cmd" | jq -r ".[] | .$column_to_grab" | sort | grep "$search_string")
    echo "${pve_api_listing[@]}"
}