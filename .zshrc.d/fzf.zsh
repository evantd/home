export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:500 {}'"

# Use ~~ as the trigger sequence instead of the default **
#export FZF_COMPLETION_TRIGGER='~~'

# Options to fzf command
export FZF_COMPLETION_OPTS='--border --info=inline'

# Use fd (https://github.com/sharkdp/fd) instead of the default find
# command for listing path candidates.
# - The first argument to the function ($1) is the base path to start traversal
# - See the source code (completion.{bash,zsh}) for the details.
_fzf_compgen_path() {
  fd --hidden --follow --exclude ".git" . "$1"
}

# Use fd to generate the list for directory completion
_fzf_compgen_dir() {
  fd --type d --hidden --follow --exclude ".git" . "$1"
}

fzf_base=~/.config/nvim/plugged/fzf
export PATH=$PATH:$fzf_base/bin

# Install fzf (via nvim) if it's not already installed.
if [ ! -x "$fzf_base/bin/fzf" ]
then
    nvim +PlugInstall +qall
fi

source $fzf_base/shell/completion.zsh
source $fzf_base/shell/key-bindings.zsh
