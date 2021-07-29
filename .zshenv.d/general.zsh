# .zshenv

export PATH=$HOME/bin:$PATH
export PATH=$PATH:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local/sbin

export LESS="MRiX"

[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh /usr/bin/lesspipe)"

if [ "x$TERM" = "xalacritty" ]
then
    COLORTERM="truecolor"
fi
