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

# Function to check if JSON file is valid
check_json_file() {
    if [ ! -s "$SSH_CONFIG_FILE" ]; then
        echo '{"hosts":[]}' > "$SSH_CONFIG_FILE"
        return
    fi
    
    if ! jq empty "$SSH_CONFIG_FILE" 2>/dev/null; then
        echo "Error: SSH hosts file is corrupted. Creating a new one."
        echo '{"hosts":[]}' > "$SSH_CONFIG_FILE"
    fi
}

# Check JSON file validity at startup
check_json_file

import_ssh_config() {
    echo "Importing hosts from ~/.ssh/config..."
    if [ ! -f "$SSH_SYSTEM_CONFIG" ]; then
        echo "SSH config file not found at $SSH_SYSTEM_CONFIG"
        return
    fi
    
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
    echo "Import completed."
}

add_host_silent() {
    local alias=$1
    local username=$2
    local hostname=$3
    local keypath=$4
    
    check_json_file
    
    local json_content=$(cat "$SSH_CONFIG_FILE")
    
    if echo "$json_content" | jq -e ".hosts[] | select(.alias == \"$alias\")" > /dev/null 2>&1; then
        return
    fi
    
    local new_host="{\"alias\":\"$alias\",\"username\":\"$username\",\"hostname\":\"$hostname\",\"keypath\":\"$keypath\"}"
    echo "$json_content" | jq ".hosts += [$new_host]" > "$SSH_CONFIG_FILE.tmp"
    mv "$SSH_CONFIG_FILE.tmp" "$SSH_CONFIG_FILE"
}

add_host() {
    local alias username hostname keypath
    
    # Use fzf as input for each field with preview
    alias=$(echo "" | fzf --print-query --preview 'echo "This will be the shortcut name for your connection"' --preview-window=up:1 | head -1)
    username=$(echo "" | fzf --print-query --preview 'echo "The SSH username (e.g., ubuntu, root, admin)"' --preview-window=up:1 | head -1)
    hostname=$(echo "" | fzf --print-query --preview 'echo "The hostname or IP address of the server"' --preview-window=up:1 | head -1)
    
    # Show existing key files in ~/.ssh for selection
    keypath=$(find ~/.ssh -type f -name "id_*" -o -name "*.pem" 2>/dev/null | fzf --preview 'ssh-keygen -l -f {} 2>/dev/null || echo "Not a valid key file"' --preview-window=up:3 --prompt="Select SSH key (ESC to skip): " || echo "")

    if [ -z "$alias" ] || [ -z "$hostname" ]; then
        echo "Alias and hostname are required. Host not added."
        return
    fi

    add_host_silent "$alias" "$username" "$hostname" "$keypath"
    echo "Host added successfully!"
}

edit_host() {
    check_json_file
    
    # Check if there are any hosts
    if [ "$(jq -r '.hosts | length' "$SSH_CONFIG_FILE" 2>/dev/null || echo "0")" -eq 0 ]; then
        echo "No hosts found to edit."
        return
    fi
    
    local selection
    selection=$(jq -r '.hosts[] | "\(.alias) (\(.username)@\(.hostname))"' "$SSH_CONFIG_FILE" | 
        fzf --preview '
            host=$(echo {} | cut -d" " -f1)
            jq -r ".hosts[] | select(.alias == \"'"$host"'\") | \"Alias: \(.alias)\nUsername: \(.username)\nHostname: \(.hostname)\nKey Path: \(.keypath)\"" "'"$SSH_CONFIG_FILE"'"
        ' --preview-window=right:50% | 
        cut -d' ' -f1)
    
    if [ -z "$selection" ]; then
        return
    fi
    
    # Get current values
    local host_info=$(jq -r ".hosts[] | select(.alias == \"$selection\")" "$SSH_CONFIG_FILE")
    local current_username=$(echo "$host_info" | jq -r '.username')
    local current_hostname=$(echo "$host_info" | jq -r '.hostname')
    local current_keypath=$(echo "$host_info" | jq -r '.keypath')
    
    # Edit values
    echo "Editing host: $selection"
    local new_username=$(echo "$current_username" | fzf --print-query --preview 'echo "Enter new username (or keep current)"' --preview-window=up:1 | head -1)
    local new_hostname=$(echo "$current_hostname" | fzf --print-query --preview 'echo "Enter new hostname (or keep current)"' --preview-window=up:1 | head -1)
    
    # Show existing key files in ~/.ssh for selection
    local new_keypath=$(find ~/.ssh -type f -name "id_*" -o -name "*.pem" 2>/dev/null | 
        (grep -F "$current_keypath" 2>/dev/null || echo "$current_keypath") | 
        fzf --preview 'ssh-keygen -l -f {} 2>/dev/null || echo "Not a valid key file"' --preview-window=up:3 --prompt="Select SSH key (ESC to keep current): " || echo "$current_keypath")
    
    # Update the host
    jq ".hosts |= map(if .alias == \"$selection\" then 
        {\"alias\": \"$selection\", \"username\": \"$new_username\", \"hostname\": \"$new_hostname\", \"keypath\": \"$new_keypath\"} 
        else . end)" "$SSH_CONFIG_FILE" > "$SSH_CONFIG_FILE.tmp"
    mv "$SSH_CONFIG_FILE.tmp" "$SSH_CONFIG_FILE"
    
    echo "Host $selection updated successfully!"
}

manage_hosts() {
    check_json_file
    
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
        *)
            # No action selected
            ;;
    esac
}

delete_host() {
    check_json_file
    
    # Check if there are any hosts
    if [ "$(jq -r '.hosts | length' "$SSH_CONFIG_FILE" 2>/dev/null || echo "0")" -eq 0 ]; then
        echo "No hosts found to delete."
        return
    fi
    
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
    check_json_file
    
    # Check if there are any hosts
    if [ "$(jq -r '.hosts | length' "$SSH_CONFIG_FILE" 2>/dev/null || echo "0")" -eq 0 ]; then
        echo "No hosts found to view."
        return
    fi
    
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
    if [ ! -s "$SSH_HISTORY_FILE" ]; then
        echo "No connection history found."
        return
    fi
    
    local selection
    selection=$(tail -n 50 "$SSH_HISTORY_FILE" | 
        fzf --tac --preview 'echo "Press enter to connect to this host"' --preview-window=up:1 | 
        awk '{print $NF}')
    
    if [ -n "$selection" ]; then
        connect "$selection"
    fi
}

connect() {
    check_json_file
    
    local selection
    if [ -z "$1" ]; then
        # Check if there are any hosts
        local host_count=$(jq -r '.hosts | length' "$SSH_CONFIG_FILE" 2>/dev/null || echo "0")
        if [ "$host_count" -eq 0 ]; then
            echo "No hosts found. Add a host first with 'add' command."
            return
        fi
        
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
            
            echo "Connecting to $selection ($username@$hostname)..."
            if [ -n "$keypath" ] && [ "$keypath" != "null" ] && [ "$keypath" != "" ]; then
                ssh "${username}@${hostname}" -i "$keypath"
            else
                ssh "${username}@${hostname}"
            fi
        else
            echo "Host not found!"
        fi
    fi
}

# Display help if no arguments and no hosts
if [ $# -eq 0 ]; then
    # Check if there are any hosts
    host_count=$(jq -r '.hosts | length' "$SSH_CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$host_count" -eq 0 ]; then
        echo "SSH Manager - Manage your SSH connections"
        echo ""
        echo "Usage:"
        echo "  $(basename "$0") add     - Add a new host"
        echo "  $(basename "$0") manage  - Manage hosts (connect, edit, delete, view)"
        echo "  $(basename "$0") import  - Import hosts from SSH config"
        echo "  $(basename "$0") history - Show connection history"
        echo "  $(basename "$0") <alias> - Connect to a host by alias"
        echo ""
        echo "No hosts found. Add a host with 'add' command or import from SSH config."
        exit 0
    fi
fi

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