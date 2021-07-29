fdfind_loc=$(which fdfind)
if [ -x "$fdfind_loc" ]
then
    ln -sf "$fdfind_loc" ~/bin/fd
fi
fd_loc=$(which fd)
if [ ! -x "$fd_loc" ]
then
    echo "Please install https://github.com/sharkdp/fd"
fi

