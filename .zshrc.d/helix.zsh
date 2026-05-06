# helix.zsh -- zsh-helix-mode + cheat sheet binding.
# Replaces the older vim.zsh.
#
# Cheat sheet (sheet.txt + style.json + build.zsh) lives in
# ~/.local/share/hxhelp/. Regenerate after content changes:
#   zsh ~/.local/share/hxhelp/build.zsh

# 1. Editor.
export EDITOR=hx VISUAL=hx

# 2. Load helix-mode plugin. It does:
#    - bindkey -N hxnor vicmd   (copies vicmd as base for normal)
#    - bindkey -N hxins viins   (copies viins as base for insert)
#    - bindkey -A hxins main    (insert mode becomes main)
source ~/.local/share/zsh-helix-mode/zsh-helix-mode.plugin.zsh

# 3. Readline conveniences carried over from old vim.zsh. These were
#    originally on `main` (== viins by default), and `main` is now hxins,
#    so they apply to insert mode as before.
bindkey '^H' backward-delete-char
bindkey '^?' backward-delete-char
bindkey '^W' backward-kill-word
bindkey '^U' kill-line

# History search on arrows (insert mode, i.e. main)
bindkey '^[[A' history-beginning-search-backward
bindkey '^[OA' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward
bindkey '^[OB' history-beginning-search-forward
bindkey '\eq' push-line-or-edit
bindkey '\M-E' push-line-or-edit
bindkey '^R' history-incremental-search-backward

# k/j history nav in normal mode. zsh-helix-mode's
# zhm_move_up_or_history_prev / _down_or_history_next already give history
# fallthrough when there's no line above/below, so this is mostly redundant
# -- keeping it makes k/j ALWAYS hit history without needing an empty
# selection. Drop if it conflicts.
bindkey -M hxnor 'k' up-line-or-search
bindkey -M hxnor 'j' down-line-or-search

# 4. Cheat sheet. The static rendered sheet lives at $HXHELP_FILE; only
#    re-render via ~/.local/share/hxhelp/build.zsh when content changes.
: ${HXHELP_FILE:=$HOME/.local/share/hxhelp/sheet.txt}

hxhelp() {
  # ~/.zshenv.d/general.zsh sets LESS=MRiX -- the X disables alt-screen,
  # so override LESS='' here. -R = render ANSI, -K = exit on ^C.
  if [[ ! -r "$HXHELP_FILE" ]]; then
    echo "hxhelp: $HXHELP_FILE not found. Run: zsh ~/.local/share/hxhelp/build.zsh" >&2
    return 1
  fi
  LESS='' command less -RK "$HXHELP_FILE"
}

# Mid-edit help: zle widget shows the cheat sheet in less's alt-screen,
# then redraws the prompt with $BUFFER intact.
hxhelp-widget() {
  zle -I            # invalidate / suspend line editor
  hxhelp            # alt-screen takes over; q to dismiss
  zle reset-prompt  # redraw prompt + restore line in place
}
zle -N hxhelp-widget

# Bind ^X? in any mode for help.
# (Don't bind bare <space> in normal mode -- zsh-helix-mode uses <space>
# as a prefix for system-clipboard ops: <space>y/p/P/R.)
bindkey -M main  '^X?' hxhelp-widget
bindkey -M hxnor '^X?' hxhelp-widget
