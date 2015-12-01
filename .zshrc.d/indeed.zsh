# Single-brace syntax because this is required in bash and sh alike
if [ -e "$HOME/env/etc/indeedrc" ]; then
    . "$HOME/env/etc/indeedrc"
fi
if ssh-add -l | grep -q edower
then
  # good!
else
  eval `ssh-agent`
  ssh-add
fi
