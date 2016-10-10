# Single-brace syntax because this is required in bash and sh alike
if [ -e "$HOME/env/etc/indeedrc" ]; then
    . "$HOME/env/etc/indeedrc"
fi
alias build='ant clean compile test package </dev/null >&log.txt & ; less +F log.txt'
