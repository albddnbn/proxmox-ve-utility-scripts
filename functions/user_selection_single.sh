function user_selection_single () {
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
Usage: $(basename "${BASH_SOURCE[0]}") [-h] -b|--backtitle back_title -t|--title menu_title -p|--pvesh pvesh_cmd -c|--column column_to_grab -a|--auto auto_return

Creates dialog menu using results from given pvesh command, column to grab, and auto return if only one option:

Available options:

-h, --help      Print this help and exit
-b, --backtitle Backtitle of the dialog
-t, --title     Title of the dialog
-p, --pvesh     pvesh command, ex: pvesh get /cluster/sdn/zones --type simple --output json
-c, --column    column to grab, ex: zone
-a, --auto      auto return option if only one
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
            -c|--column)
                column_to_grab="$2"
                shift 2
                ;;
            -a|--auto)
                auto_return="$2"
                shift 2
                ;;
            *)
            echo "Unknown option: $1"
            return 1
            ;;
        esac
    done

    #apt install jq dialog -y 2>&1 >/dev/null

    cmd=(dialog --clear --backtitle "$back_title" --title "$menu_title" --menu "$menu_title" 22 76 16)
    # echo "cmd: ${cmd[@]}"
    count=0

    options=()
    ##
    test_options=$(eval "$pvesh_cmd" | jq -r ".[] | .$column_to_grab" | sort)


    matching_options=()
    for single_option in $test_options; do
        # echo "single_option: $single_option"
        added_string="$((++count)) "$single_option""
        matching_options+=($single_option)
        options+=($added_string)
    done

    length=${#matching_options[@]}
    if [[ ($length -gt 1) || ("$auto_return" == "0") ]]; then
        choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)

        printf -v final_choice "%s\n" "${choices[@]}"

        ## subtract one from final_choice to get index
        final_choice=$((final_choice-1))

        ## 'return' the selected option
        echo "${matching_options[$final_choice]}"
    else
        echo "$test_options"
    fi
}