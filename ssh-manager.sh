#!/bin/bash

SSH_CONFIG_FILE="$HOME/.ssh/ssh_hosts.json"
SSH_HISTORY_FILE="$HOME/.ssh/ssh_history"
SSH_SYSTEM_CONFIG="$HOME/.ssh/config"

# Check for required commands
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq first."
    echo "Ubuntu/Debian: sudo apt install jq"
    echo "MacOS: brew install jq"
    exit 1
fi

if ! command -v fzf &> /dev/null; then
    echo "Error: fzf is required but not installed. Please install fzf first."
    echo "Ubuntu/Debian: sudo apt install fzf"
    echo "MacOS: brew install fzf"
    exit 1
fi

# Create files if they don't exist
if [ ! -f "$SSH_CONFIG_FILE" ]; then
    echo '{"hosts":[]}' > "$SSH_CONFIG_FILE"
fi
touch "$SSH_HISTORY_FILE"

import_ssh_config() {
    echo "Importing hosts from ~/.ssh/config..."
    while IFS= read -r line; do
        if [[ $line =~ ^Host[[:space:]]+([^*][^[:space:]]+)$ ]]; then
            host_alias="${BASH_REMATCH[1]}"
            user=""
            hostname=""
            identity=""
            while IFS= read -r subline; do
                [[ $subline =~ ^[[:space:]]*User[[:space:]]+(.*) ]] && user="${BASH_REMATCH[1]}"
                [[ $subline =~ ^[[:space:]]*HostName[[:space:]]+(.*) ]] && hostname="${BASH_REMATCH[1]}"
                [[ $subline =~ ^[[:space:]]*IdentityFile[[:space:]]+(.*) ]] && identity="${BASH_REMATCH[1]}"
                [[ $subline =~ ^Host[[:space:]] ]] && break
            done
            
            if [ -n "$hostname" ]; then
                add_host_silent "$host_alias" "$user" "$hostname" "$identity"
            fi
        fi
    done < "$SSH_SYSTEM_CONFIG"
}

add_host_silent() {
    local alias=$1
    local username=$2
    local hostname=$3
    local keypath=$4
    
    local json_content=$(cat "$SSH_CONFIG_FILE")
    
    if echo "$json_content" | jq -e ".hosts[] | select(.alias == \"$alias\")" > /dev/null; then
        return
    fi
    
    local new_host="{\"alias\":\"$alias\",\"username\":\"$username\",\"hostname\":\"$hostname\",\"keypath\":\"$keypath\"}"
    echo "$json_content" | jq ".hosts += [$new_host]" > "$SSH_CONFIG_FILE"
}

add_host() {
    local alias username hostname keypath
    
    # Use fzf as input for each field with preview
    echo "Enter host alias:" | fzf --print-query --preview 'echo "This will be the shortcut name for your connection"' --preview-window=up:1 | head -1 | read -r alias
    echo "Enter username:" | fzf --print-query --preview 'echo "The SSH username (e.g., ubuntu, root, admin)"' --preview-window=up:1 | head -1 | read -r username
    echo "Enter hostname/IP:" | fzf --print-query --preview 'echo "The hostname or IP address of the server"' --preview-window=up:1 | head -1 | read -r hostname
    
    # Show existing key files in ~/.ssh for selection
    keypath=$(find ~/.ssh -type f -name "id_*" -o -name "*.pem" | fzf --preview 'ssh-keygen -l -f {} 2>/dev/null || echo "Not a valid key file"' --preview-window=up:3 --prompt="Select SSH key (ESC to skip): " || echo "")

    add_host_silent "$alias" "$username" "$hostname" "$keypath"
    echo "Host added successfully!"
}

manage_hosts() {
    local action
    action=$(echo -e "connect\ndelete\nedit\nview" | fzf --preview '
        case {} in
            "connect") echo "Connect to a host";;
            "delete")  echo "Delete a host";;
            "edit")   echo "Edit host details";;
            "view")   echo "View host details";;
        esac
    ' --preview-window=up:1)

    case $action in
        "connect")
            connect
            ;;
        "delete")
            delete_host
            ;;
        "edit")
            edit_host
            ;;
        "view")
            view_host
            ;;
    esac
}

delete_host() {
    local selection
    selection=$(jq -r '.hosts[] | "\(.alias) (\(.username)@\(.hostname))"' "$SSH_CONFIG_FILE" | 
        fzf --preview 'echo "Press enter to delete this host"' --preview-window=up:1 | 
        cut -d' ' -f1)
    
    if [ -n "$selection" ]; then
        jq ".hosts |= map(select(.alias != \"$selection\"))" "$SSH_CONFIG_FILE" > "$SSH_CONFIG_FILE.tmp"
        mv "$SSH_CONFIG_FILE.tmp" "$SSH_CONFIG_FILE"
        echo "Host $selection deleted"
    fi
}

view_host() {
    jq -r '.hosts[] | "\(.alias) (\(.username)@\(.hostname))"' "$SSH_CONFIG_FILE" |
        fzf --preview '
            host=$(echo {} | cut -d" " -f1)
            jq -r ".hosts[] | select(.alias == \"'"$host"'\") | \"Alias: \(.alias)\nUsername: \(.username)\nHostname: \(.hostname)\nKey Path: \(.keypath)\"" "'"$SSH_CONFIG_FILE"'"
        ' --preview-window=right:50%
}

record_history() {
    local alias=$1
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $alias" >> "$SSH_HISTORY_FILE"
}

show_history() {
    local selection
    selection=$(tail -n 50 "$SSH_HISTORY_FILE" | 
        fzf --tac --preview 'echo "Press enter to connect to this host"' --preview-window=up:1 | 
        awk '{print $NF}')
    
    if [ -n "$selection" ]; then
        connect "$selection"
    fi
}

connect() {
    local selection
    if [ -z "$1" ]; then
        selection=$(jq -r '.hosts[] | "\(.alias) (\(.username)@\(.hostname))"' "$SSH_CONFIG_FILE" | 
            fzf --preview '
                host=$(echo {} | cut -d" " -f1)
                jq -r ".hosts[] | select(.alias == \"'"$host"'\") | \"Alias: \(.alias)\nUsername: \(.username)\nHostname: \(.hostname)\nKey Path: \(.keypath)\"" "'"$SSH_CONFIG_FILE"'"
            ' --preview-window=right:50% | 
            cut -d' ' -f1)
    else
        selection=$1
    fi

    if [ -n "$selection" ]; then
        host_info=$(jq -r ".hosts[] | select(.alias == \"$selection\")" "$SSH_CONFIG_FILE")
        if [ -n "$host_info" ] && [ "$host_info" != "null" ]; then
            username=$(echo "$host_info" | jq -r '.username')
            hostname=$(echo "$host_info" | jq -r '.hostname')
            keypath=$(echo "$host_info" | jq -r '.keypath')
            
            record_history "$selection"
            
            if [ -n "$keypath" ] && [ "$keypath" != "null" ]; then
                ssh "${username}@${hostname}" -i "$keypath"
            else
                ssh "${username}@${hostname}"
            fi
        else
            echo "Host not found!"
        fi
    fi
}

case "$1" in
    "add")
        add_host
        ;;
    "import")
        import_ssh_config
        ;;
    "history")
        show_history
        ;;
    "manage")
        manage_hosts
        ;;
    *)
        if [ -n "$1" ]; then
            connect "$1"
        else
            manage_hosts
        fi
        ;;
esac