# zz-bin-first.zsh -- ensure ~/bin is at PATH position 1.
#
# ~/.zshenv.d/general.zsh already does `export PATH=$HOME/bin:$PATH` early,
# but Indeed's shell init chain plus /etc/zprofile (path_helper) plus
# ~/.zprofile (brew shellenv) all run between .zshenv and .zshrc, and they
# routinely reorder PATH so that ~/bin ends up well past position 1.
#
# This file (sorts last in .zshrc.d/ via zz- prefix) re-pins ~/bin to the
# front, both at shell init and on every precmd. The precmd hook is
# defense-in-depth: anything that mutates PATH between prompts (Indeed's
# async repo updaters, nvm, mise, direnv chpwd hooks, etc.) gets undone on
# the next prompt redraw.
#
# Why this matters: scripts I drop in ~/bin (including the git shim used
# during the jj adoption experiment) need to win over their counterparts
# in /opt/homebrew/bin and /usr/bin. Reordering PATH explicitly is more
# reliable than fighting every later-running init file individually.
#
# Non-interactive shells: ~/.zshenv.d/general.zsh already puts ~/bin first
# and nothing else runs to reorder it (zprofile/zshrc don't fire), so they
# don't need this hook.

_ensure_bin_first() {
  # Fast path: already at position 1, nothing to do.
  case "$PATH" in
    "$HOME/bin:"*) return 0 ;;
  esac
  # Strip every existing occurrence of ~/bin from PATH, then prepend it
  # below. A naive "if not present, prepend" would no-op when ~/bin is at
  # position 9, leaving it at 9; strip-then-prepend guarantees position 1.

  # Wrap with sentinel colons so every entry is bracketed by `:` (uniform
  # match pattern below).
  PATH=":$PATH:"

  # Global parameter expansion: replace every `:$HOME/bin:` with a single
  # `:`. The `\/` escapes the slash so zsh doesn't treat it as the
  # pattern/replacement separator.
  PATH="${PATH//:$HOME\/bin:/:}"

  # Strip the sentinel colons we added above.
  PATH="${PATH#:}"
  PATH="${PATH%:}"

  export PATH="$HOME/bin:$PATH"
}

_ensure_bin_first

autoload -Uz add-zsh-hook
add-zsh-hook precmd _ensure_bin_first
