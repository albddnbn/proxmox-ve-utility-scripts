## offers selection based on dialog command, pvesh command, and column to grab
function user_selection_single () {
    ## -t | --title = title of the dialog/menu
    ## -p | --pvesh = pvesh command, ex: pvesh get /cluster/sdn/zones --type simple --noborder --output json
    ## -c | --col = column to grab, ex: zone
    ## -a | --auto = auto return first option if only one
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

    cmd=(dialog --keep-tite --backtitle "$back_title" --title "$menu_title" --menu "$menu_title" 22 76 16)
    # echo "cmd: ${cmd[@]}"
    count=0

    options=()
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

function run_spinner () {
    local pid=$1 # Process Id of the previous running command
    local spinner_message=$2
    local spin='-\|/'

    local color='\033[1;32;1;42m'
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


## Check if item exists using given pvesh command, search string, and column to grab:
# Ex: check_pve_item -p "pvesh get /cluster/resources --type vm --noborder --output json" -s "test" -c "name"
function check_pve_item () {
    ## -p | --pvesh = pvesh command, ex: pvesh get /cluster/sdn/zones --type simple --noborder --output json
    ## -s | --search = search string, ex: "zone1"
    ## -c | --column = column to grab, ex: zone
    while [ "$#" -gt 0 ]; do
        case "$1" in
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

    ## Get listing from api endpoint:
    mapfile -t pve_api_listing <<< $(eval "$pvesh_cmd" | jq -r ".[] | .$column_to_grab" | sort | grep "$search_string")
    echo "${pve_api_listing[@]}"
}

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

function create_checklist () {
    ## -t | --title = title of the dialog/menu
    ## -p | --pvesh = pvesh command, ex: pvesh get /cluster/sdn/zones --type simple --noborder --output json
    ## -c | --col = column to grab, ex: zone
    ## -a | --auto = auto return first option if only one
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

    cmd=(dialog --separate-output --checklist \"$menu_title\" 22 76 16)
    # echo "cmd: ${cmd[@]}"

    formatted_checklist_options=()
    main_col_results=$(eval "$pvesh_cmd" | jq -r ".[] | .$column_to_grab")
    mapfile -t main_results <<< "$main_col_results"
    secondary_column=$(eval "$pvesh_cmd" | jq -r ".[] | .$secondary_column")
    mapfile -t sec_col_results <<< "$secondary_column"


    ## Some different ways to format output with jq, I'm putting them here for safekeeping:
    ## pvesh get /cluster/resources --type vm --noborder --output json | jq '. [] | {(.name): .vmid}'
    ## pvesh get /cluster/resources --type vm --noborder --output json | jq '. [] | "\(.vmid) \(.name)"'
    ## pvesh get /cluster/resources --type vm --noborder --output json | jq -r '. [] | "{id: \(.vmid),name: \(.name)}"'
    ## results=$(pvesh get /cluster/resources --type vm --noborder --output json | jq -r '. [] | "{id: \(.vmid),name: \(.name)}"')
    
    count=0
    for single_option in $main_col_results; do
        target_index=$count
        ## increment count
        count=$((count+1))
        ## Create the display_name for the option:
        display_name="$single_option ${sec_col_results[$target_index]}"
        # echo "setting display name: $single_option"
        formatted_checklist_string="$count \"$display_name\" off"
        # echo "added_string: $formatted_checklist_string"
        formatted_checklist_options+=($formatted_checklist_string)
    done

    # echo "executing cmd: ${cmd[@]} ${formatted_checklist_options[@]}"
    choices=$(eval "${cmd[@]} ${formatted_checklist_options[@]}" 2>&1 >/dev/tty)

    # echo "$choices"

    final_results=()
    for choice in $choices; do
    # echo "adding $choice to the list.."
        ## subtract one from final_choice to get index
        final_choice=$((choice-1))
        # echo "adding: ${main_results[$final_choice]}"
        final_results+=("${main_results[$final_choice]}")
    done

    echo "${final_results[@]}"
}