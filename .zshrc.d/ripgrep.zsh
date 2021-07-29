rg_loc=$(which rg)
if [ ! -x "$rg_loc" ]
then
    echo "Please install https://github.com/BurntSushi/ripgrep"
fi

