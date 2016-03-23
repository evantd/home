# .zshrc.d/prompt vim: set ft=zsh:

if [[ "$(uname -s)" == "Darwin" ]]; then
    # No plan for Darwin yet.
else

    function update_ssh_auth_sock () {
        export SSH_AUTH_SOCK=$(find /tmp/ssh-* -user `whoami` -name agent\* -printf '%T@ %p\n' 2>/dev/null | sort -k 1nr | sed 's/^[^ ]* //' | head -n 1)
    }

    typeset -a precmd_functions
    if [ $ZSH_MAJOR_VERSION -gt 4 -o \( $ZSH_MAJOR_VERSION -eq 4 -a $ZSH_MINOR_VERSION -ge 2 \) ]
    then
        precmd_functions+=update_ssh_auth_sock
    else
        precmd_functions[$(($#precmd_functions+1))]=update_ssh_auth_sock
    fi

fi
