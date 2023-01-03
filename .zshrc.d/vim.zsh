# .zshrc.d/vim.zsh # vim: set ft=zsh:

export EDITOR=nvim VISUAL=nvim
bindkey -v # this should be covered by EDITOR, but sometimes isn't

# let me backspace past where I entered insert mode
bindkey '^H' backward-delete-char
bindkey '^?' backward-delete-char
bindkey '^W' backward-kill-word
bindkey '^U' kill-line

# command mode with commands
bindkey -M vicmd ':' execute-named-cmd

# sweet history searching and editing
bindkey '^[[A' history-beginning-search-backward
bindkey '^[OA' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward
bindkey '^[OB' history-beginning-search-forward
bindkey '\eq' push-line-or-edit
bindkey '\M-E' push-line-or-edit

# similar, but slightly different, for command mode
bindkey -M vicmd 'k' up-line-or-search
bindkey -M vicmd 'j' down-line-or-search

# these are backward and non-incremental by default
bindkey -M vicmd '?' history-incremental-search-backward
bindkey -M vicmd '/' history-incremental-search-forward

# keep it handy during insert mode too (especially useful *during* isearch)
bindkey '^R' history-incremental-search-backward

# predict what I'll do next when searching
#bindkey -M isearch '^J' accept-and-infer-next-history
#bindkey -M isearch '^M' accept-and-infer-next-history
