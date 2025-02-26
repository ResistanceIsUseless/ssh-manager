# SSH Manager

A simple command-line tool to manage SSH connections with easy-to-remember aliases.

## Features

- Add and manage SSH connections with aliases
- Import hosts from existing SSH config
- Connection history tracking
- Interactive selection with fuzzy search (fzf)
- Command completion for zsh

## Requirements

- jq (JSON processor)
- fzf (Fuzzy finder)

## Installation

1. Clone this repository or download the `ssh-manager.sh` script
2. Make the script executable: `chmod +x ssh-manager.sh`
3. Move it to your SSH directory: `mv ssh-manager.sh ~/.ssh/`
4. Add the following to your `.zshrc`:

```
# SSH Manager
alias sshm="~/.ssh/ssh-manager.sh"

# Command completion for sshm
_ssh_manager_completion() {
    local -a commands
    commands=(
        'add:Add a new host'
        'manage:Manage existing hosts'
        'import:Import hosts from SSH config'
        'history:Show connection history'
    )
    
    # Add existing hosts from the JSON file
    if [[ -f ~/.ssh/ssh_hosts.json ]]; then
        local hosts=($(jq -r '.hosts[].alias' ~/.ssh/ssh_hosts.json))
        for host in $hosts; do
            commands+=("$host:Connect to $host")
        done
    fi

    _describe 'command' commands
}

compdef _ssh_manager_completion sshm
```

## Usage

- `sshm add` - Add a new SSH connection
- `sshm manage` - Manage existing connections (connect, edit, delete, view)
- `sshm import` - Import hosts from your SSH config file
- `sshm history` - Show connection history
- `sshm <alias>` - Connect directly to a saved host

## Configuration

SSH Manager stores host information in `~/.ssh/ssh_hosts.json` with the following structure:

```
{
  "hosts": [
    {
      "alias": "flint",
      "username": "staticbunny",
      "hostname": "flint.floof.ninja",
      "keypath": "~/.key/pub"
    }
  ]
}
```

## Example

```
# Add a new host
$ sshm add

# Connect to a host
$ sshm flint

# Import hosts from SSH config
$ sshm import

# View connection history
$ sshm history
```