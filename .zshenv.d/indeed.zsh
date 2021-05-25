export INDEED_PROJECT_DIR="$HOME/indeed"

export PATH="$INDEED_PROJECT_DIR/hobo/bin:$PATH"
export PATH="$PATH:$INDEED_PROJECT_DIR/progex/progex-init/progex-scripts"
# OPTIONAL, but recommended: Add ~/env/bin to your PATH to use the shared shell scripts from delivery/env
if [ -d /opt/indeed/env ]; then
  export INDEED_ENV_DIR="/opt/indeed/env"
else
  export INDEED_ENV_DIR="$HOME/env"
fi
export PATH="$INDEED_ENV_DIR/bin:$PATH"
# indeedrc depends on a different mktemp
export PATH="/usr/local/opt/coreutils/libexec/gnubin:$PATH"
export INDEED_JAVADEV_DIR="$INDEED_PROJECT_DIR/javadev"
export PATH="$INDEED_JAVADEV_DIR/bin:$PATH"
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

export IVY_IGNORE_RELEASE=0

export INDEED_OFFICE="cvm"
export INDEED_TEAMS="indapply dradis resume"

# Save disk space by discarding previous versions of artifacts.
export PREVIOUS_ITEMS_TO_KEEP=0
export MAX_KEPT=1
