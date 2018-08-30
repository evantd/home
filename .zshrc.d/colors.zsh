# Base16 Shell
BASE16_SHELL="$HOME/.config/base16-shell/"
BASE16_HELPER="$BASE16_SHELL/profile_helper.sh"
if [ -n $PS1 ]
then
  if [ ! -s "$BASE16_HELPER" ]
  then
    git clone https://github.com/chriskempson/base16-shell.git "$BASE16_SHELL"
  fi
  if [ -s "$BASE16_HELPER" ]
  then
  eval "$("$BASE16_HELPER")"
    _base16 "$BASE16_SHELL/scripts/base16-bright.sh" bright
  fi
fi
