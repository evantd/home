# .zshrc.d/completion.zsh # vim: set ft=zsh:

autoload -U compinit
zstyle ':completion:*' menu select=4
zstyle ':completion:*' completer _expand _complete _correct _approximate _history
zstyle ':completion:*:descriptions' format 'Completing %d:'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' insert-unambiguous
# Disable hostname completion
zstyle ':completion:*' hosts off
compinit
