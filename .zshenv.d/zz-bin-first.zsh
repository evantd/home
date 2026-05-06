# zz-bin-first.zsh -- ensure ~/bin is at PATH position 1.
#
# Sorts last in .zshenv.d/ (zz- prefix) so it runs after general.zsh and
# indeed.zsh, both of which prepend their own dirs (~/bin and ~/.krew/bin
# respectively). This is the ONLY chance to fix PATH for non-interactive
# shells (which never source .zshrc).
#
# Interactive shells re-enforce via ~/.zshrc.d/zz-bin-first.zsh, which
# also installs a precmd hook to defend against later mutations.

# Strip every existing occurrence of ~/bin from PATH, then prepend it
# unconditionally below. A naive "if not present, prepend" would no-op when
# ~/bin is already somewhere in PATH (e.g., position 9), leaving it there;
# strip-then-prepend guarantees position 1.
if [[ ":$PATH:" == *":$HOME/bin:"* ]]; then
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
fi
export PATH="$HOME/bin:$PATH"
