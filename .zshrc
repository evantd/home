# .zshrc

setopt nohup localoptions localtraps

for rcfile in ~/.zshrc.d/*
do
    source "$rcfile"
done
