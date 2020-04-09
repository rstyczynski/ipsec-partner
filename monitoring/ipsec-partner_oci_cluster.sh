#!/bin/bash

# cluster wrapper on ipsec-partner_oci.sh
# Goal:
# 1. report only from node hosting services
# 2. if service is down report on both nodes

export resource_name=ipsec_cluster_libreswan
libreswan_state_line=$(pcs resource show | perl -ne 'BEGIN{$resource_name=$ENV{'resource_name'};} 
m{\s*$resource_name\s+\(([\w:]+)\):\s+(\w+)\s+([\w-]+)} && print "$1 $2 $3\n"')
read -ra ADDR <<<"$libreswan_state_line"

libreswan_state=${ADDR[1]}
libreswan_host=${ADDR[2]}

case $libreswan_state in
Started)
    if [ $libreswan_host == $(hostname -s) ]; then
        echo "Started on this node. Reporting status. Node: $libreswan_host"
        /opt/ipsec-partner/sbin/ipsec-partner_oci.sh $@
    else
        echo "Started on other node. Status reporting skipped. Node: $libreswan_host"
    fi
    ;;
Stopped)
    echo "Stopped. Reporting status. Node: $libreswan_host"
    /opt/ipsec-partner/sbin/ipsec-partner_oci.sh $@
    ;;
*)
    echo "Not on this node or stopped."
    ;;
esac
