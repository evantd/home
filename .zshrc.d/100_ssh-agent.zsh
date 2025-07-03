# .zshrc.d/prompt vim: set ft=zsh:

builtin autoload -Uz add-zsh-hook

if [[ "$(uname -s)" == "Darwin" ]]; then
    # No plan for Darwin yet.
else

    function update_ssh_auth_sock () {
        export SSH_AUTH_SOCK=$(find /tmp/ssh-* -user `whoami` -name agent\* -printf '%T@ %p\n' 2>/dev/null | sort -k 1nr | sed 's/^[^ ]* //' | head -n 1)
    }

    add-zsh-hook precmd update_ssh_auth_sock

fi
