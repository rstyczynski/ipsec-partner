#!/bin/bash

function generateKey {
    ipsec_key=$1
    openssl genrsa -out $ipsec_key.pem 2048
    openssl rsa -pubout -in $ipsec_key.pem -out $ipsec_key\_public.pem
    openssl rsa -pubout -outform DER -in $ipsec_key.pem | openssl md5 -c
    ipsec_key_fingerprint=$(openssl rsa -pubout -outform DER -in $ipsec_key.pem | openssl md5 -c | tr -d ' ' | cut -d= -f2)
    echo 
    echo "Key generated."
    echo
    echo "Register this key fingerprint:"
    echo $ipsec_key_fingerprint
    echo
    echo "Register this key in User's API Keys:"
    cat $ipsec_key\_public.pem
}

function buildOCIconfig {
    cat >config  <<EOF
    [DEFAULT]
    user=$user_OCID
    fingerprint=$ipsec_key_fingerprint
    key_file=~/.oci/$ipsec_key.pem
    tenancy=$tenancy
    region=$region
EOF

    echo "Verify if config looks ok:"
    cat config
}