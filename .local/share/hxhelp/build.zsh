#!/usr/bin/env zsh
# build.zsh -- regenerate the hxhelp cheat sheet (sheet.txt) from markdown.
#
# Run: zsh ~/.local/share/hxhelp/build.zsh
#
# Why this lives here, not in ~/.zshrc.d:
#   The rendered sheet.txt is a static artifact. The shell rc only needs to
#   `less` it. Keeping the build logic + markdown source out of the rc keeps
#   shell startup fast and avoids loading glow until/unless you regenerate.

set -e

DIR=${0:A:h}
STYLE=${DIR}/style.json
OUT=${DIR}/sheet.txt
COLW=${HXHELP_COLW:-60}

_hxhelp_left() {
  cat <<'EOF'
# helix

Motion SELECTS, then verb ACTS.
`wd` = select-word-then-delete.

## Select

| Key | Action |
|---|---|
| `w` `b` `e`     | word fwd / back / end |
| `W` `B` `E`     | long-word (whitespace) |
| `f<c>` `t<c>`   | find / till char |
| `F<c>` `T<c>`   | same, backwards |
| `;` `,`         | repeat / reverse f/t |
| `x`             | whole line |
| `%`             | all |
| `miw` `maw`     | inner / around word |
| `s<re><Ret>`    | split selection by regex |

## Move (no select)

| Key | Action |
|---|---|
| `gh` `gl`       | line start / end |
| `gs`            | first non-whitespace |
| `gg` `ge`       | buffer start / end |
EOF
}

_hxhelp_right() {
  # Leading `&nbsp;` blocks push `## Edit` down so it lines up with `## Select`
  # on the left. Each `&nbsp;\n\n` renders as one blank line. Tune count if
  # _hxhelp_left's preamble changes.
  cat <<'EOF'
&nbsp;

&nbsp;

&nbsp;

&nbsp;

&nbsp;

## Edit

| Key | Action |
|---|---|
| `d` `c`         | delete / change |
| `y` `p` `P`     | yank / paste after / before |
| `r<c>`          | replace EACH selected char |
| `R`             | replace selection with yank |
| `u` `U`         | undo / redo |
| `~`             | swap case |
| <code>\`</code> / `Alt-` <code>\`</code> | to lower / upper |
| <code>&#124;</code> | shell pipe selection |
|                 |   |

## Multi-cursor

| Key | Action |
|---|---|
| `,` `Alt-,`     | drop secondary / primary cursor |
| `;` `Alt-;`     | collapse / flip anchor |
| `(` `)`         | rotate selections |

[Full keymap →](https://docs.helix-editor.com/keymap.html)
EOF
}

# Render. mktemp suffix `.md` matters: glow uses extension to detect markdown
# and falls back to plain-text mode without it.
tmpL=$(mktemp -t hxhelp.XXXXXX.md)
tmpR=$(mktemp -t hxhelp.XXXXXX.md)
outL=$(mktemp -t hxhelp.XXXXXX)
outR=$(mktemp -t hxhelp.XXXXXX)
trap 'rm -f "$tmpL" "$tmpR" "$outL" "$outR"' EXIT

_hxhelp_left  > "$tmpL"
_hxhelp_right > "$tmpR"

# glow gotchas:
#   * It auto-detects "non-TTY stdout" when piped/redirected and drops styling.
#     Forcing -s with an explicit style file skips that path.
#   * It probes the terminal via stderr; suppressing stderr avoids the
#     responses leaking into the next program's input.
glow -s "$STYLE" -w "$COLW" "$tmpL" </dev/null 2>/dev/null > "$outL"
glow -s "$STYLE" -w "$COLW" "$tmpR" </dev/null 2>/dev/null > "$outR"
paste -d ' ' "$outL" "$outR" > "$OUT"

echo "hxhelp: rebuilt $OUT ($(wc -l < $OUT) lines)"
