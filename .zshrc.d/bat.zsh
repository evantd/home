batcat_loc=$(which batcat)
if [ -x "$batcat_loc" ]
then
    ln -sf "$batcat_loc" ~/bin/bat
fi
bat_loc=$(which bat)
if [ -x "$bat_loc" ]
then
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
else
    echo "Please install https://github.com/sharkdp/bat"
fi
