export INDEED_PROJECT_DIR="$HOME/indeed"

export PATH="$INDEED_PROJECT_DIR/hobo/bin:$PATH"
export PATH="$PATH:$INDEED_PROJECT_DIR/progex/progex-init/progex-scripts"
# OPTIONAL, but recommended: Add ~/env/bin to your PATH to use the shared shell scripts from delivery/env
export PATH="$HOME/env/bin:$PATH"
# indeedrc depends on a different mktemp
export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
export PATH="$INDEED_PROJECT_DIR/javadev/ant/bin:$PATH"

export PROGEX_EVAL_DIR="$INDEED_PROJECT_DIR/progex/progex-eval"

export INDEED_OFFICE="seaoff"
export INDEED_TEAMS="dradis resume"
