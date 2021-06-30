# .zshrc.d/prompt vim: set ft=zsh:

function getZshrcGitCommit {
    git --git-dir ~/.git log -1 --format=format:%H -- .zshenv-personal .zshenv.d .zprofile-personal .zprofile.d .zshrc-personal .zshrc.d
}
export ZSHRC_GIT_COMMIT=`getZshrcGitCommit`

autoload colors
colors
typeset -A pp # _P_rompt _P_arts
pp[end]="$bg[default]$fg_no_bold[default]"
pp[punct]="$bg[default]$fg_bold[default]"
pp[level]="$bg[default]$fg_no_bold[default]"
pp[jobs]="$bg[default]$fg_no_bold[default]"
if [ "x$USER" = "xedower" ]
then
    pp[user]="$bg[default]$fg_bold[green]"
else
    pp[user]="$bg[default]$fg_bold[red]"
fi
if [ "x`hostname`" = "xedower.desktop.amazon.com" ]
then
    pp[host]="$bg[default]$fg_bold[green]"
else
    pp[host]="$bg[default]$fg_bold[red]"
fi
pp[path]="$bg[default]$fg_no_bold[default]"

function update_prompt_colors {
    # make nasty colors when I don't have a valid kerberos ticket or my home repo is out-of-date

    if [ "$KRB_IN_USE" = "yes" ]
    then
        if klist -5cs
        then
            auth_up_to_date="yes"
        else
            auth_up_to_date="no"
        fi
    else
        auth_up_to_date="yes"
    fi

    if [ "$auth_up_to_date" = "yes" ]
    then
        if ~/bin/ghafh-up-to-date
        then
            if [ "x$ZSHRC_GIT_COMMIT" = "x`getZshrcGitCommit`" ]
            then
                pp[punct]="$bg[default]$fg_bold[default]"
            else
                pp[punct]="$bg[cyan]$fg_bold[default]"
            fi
        else
            pp[punct]="$bg[yellow]$fg_bold[default]"
        fi
    else
        pp[punct]="$bg[red]$fg_bold[default]"
    fi
}
typeset -a precmd_functions
if [ $ZSH_MAJOR_VERSION -gt 4 -o \( $ZSH_MAJOR_VERSION -eq 4 -a $ZSH_MINOR_VERSION -ge 2 \) ]
then
    precmd_functions+=update_prompt_colors
else
    precmd_functions[$(($#precmd_functions+1))]=update_prompt_colors
fi

setopt prompt_subst # expand variables (etc.) in prompt at display time
if [ $ZSH_MAJOR_VERSION -gt 4 -o \( $ZSH_MAJOR_VERSION -eq 4 -a $ZSH_MINOR_VERSION -ge 2 \) ]
then
    PS1='%{${pp[punct]}%}[' # [
    PS1+='%{${pp[user]}%}%n' # user
    PS1+='%{${pp[punct]}%}@' # @
    PS1+='%{${pp[host]}%}%m' # host
    PS1+='%{${pp[punct]}%}:' # :
    PS1+='%{${pp[path]}%}%1~' # path
    PS1+='%{${pp[punct]}%}]' # ]
    PS1+='%{${pp[level]}%}%L' # $SHLVL
    PS1+='%{${pp[punct]}%}^' # ^
    PS1+='%{${pp[jobs]}%}%j' # number of jobs
    PS1+='%{${pp[punct]}%}%#' # % for normal users, # for priveleged users
    PS1+='%{${pp[end]}%} ' # return formatting to normal and end prompt with a space
else
    PS1='%{${pp[punct]}%}[%{${pp[user]}%}%n%{${pp[punct]}%}@%{${pp[host]}%}%m%{${pp[punct]}%}:%{${pp[path]}%}%1~%{${pp[punct]}%}]%{${pp[level]}%}%L%{${pp[punct]}%}^%{${pp[jobs]}%}%j%{${pp[punct]}%}%#%{${pp[end]}%} '
fi
export PS1
