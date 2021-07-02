if [[ -r /usr/local/lib/sga-env.sh ]]; then
    source /usr/local/lib/sga-env.sh
elif [[ -r /usr/local/bin/sga-env.sh ]]; then
    source /usr/local/bin/sga-env.sh
fi
