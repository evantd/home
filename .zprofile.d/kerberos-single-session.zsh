if [ "x" '!=' "x$KRB5CCNAME" ]
then
    rm -f /tmp/krb5cc_$UID
    cp -a $(echo $KRB5CCNAME | sed -e 's/^FILE://') /tmp/krb5cc_$UID
    unset KRB5CCNAME
    export KRB_IN_USE=yes
else
    export KRB_IN_USE=no
fi
