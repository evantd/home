# Single-brace syntax because this is required in bash and sh alike
if [ -e "$HOME/env/etc/indeedrc" ]; then
    . "$HOME/env/etc/indeedrc"
fi
alias build='ant clean npm-build npm-test compile test package static </dev/null >&log.txt & ; less +F log.txt'
export AUTO_CHECK_REPOS=$INDEED_PROJECT_DIR/hobo:$INDEED_PROJECT_DIR/standalone-dradishost:$INDEED_PROJECT_DIR/dradis-hobo-resources:$INDEED_PROJECT_DIR/rhonedelta:$AUTO_CHECK_REPOS

