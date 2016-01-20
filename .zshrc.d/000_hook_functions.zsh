# .zshrc.d/hook_functions.zsh # vim: set ft=zsh:

# zsh 4.2 just runs (e.g.) precmd
# zsh 4.3 runs precmd followed by all the functions named in precmd_functions
# this defines precmd in 4.2 to run all the functions named in precmd_functions
# Example:
# functions precmd { f0 }
# precmd_functions=(f1, f2, f3)
# 4.2  runs: f0
# 4.3  runs: f0, f1, f2, f3
# this runs: f1, f2, f3

ZSH_MAJOR_VERSION=`echo $ZSH_VERSION | cut -d. -f1`
ZSH_MINOR_VERSION=`echo $ZSH_VERSION | cut -d. -f2`

if [ $ZSH_MAJOR_VERSION -lt 4 -o \( $ZSH_MAJOR_VERSION -eq 4 -a $ZSH_MINOR_VERSION -lt 3 \) ]
then
    for hook in chpwd periodic precmd preexec zshaddhistory zshexit
    do
        eval "typeset -a ${hook}_functions"
        eval "function $hook {
            for func in \$${hook}_functions
            do
                eval \$func
            done
        }"
    done
fi
