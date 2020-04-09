#!/bin/bash

cluster_config=$1

#
# functions
#
function j2y() {
    ruby -ryaml -rjson -e 'puts YAML.dump(JSON.parse(STDIN.read))'
}

function y2j() {
    ruby -ryaml -rjson -e 'puts JSON.dump(YAML.load(STDIN.read))'
}

function getPrimaryIp() {
    export ifname=$1

    ip -o addr | perl -ne 'BEGIN{$ifname=$ENV{'ifname'};}  m{\d+:\s+$ifname\s+inet\s+([\d\.]+)\/(\d+)} && print "$ifname $1 $2\n"' | head -1 | cut -d' ' -f2

}
#
# get parameters
#
function getConfiguration() {
    cluster_nodes=$(cat $cluster_config | y2j | jq -r .ipsec_partner.cluster.nodes[])
    pass=$(cat $cluster_config | y2j | jq -r .ipsec_partner.cluster.pass)

    public_ip=$(cat $cluster_config | y2j | jq -r .ipsec_partner.public.ip)
    public_ip_vnic_no=$(cat $cluster_config | y2j | jq -r .ipsec_partner.public.vnic_no)
    public_ip_oicd=$(cat $cluster_config | y2j | jq -r .ipsec_partner.public.oicd)

    private_ip1=$(cat $cluster_config | y2j | jq -r .ipsec_partner.private[0].ip)
    private_ip1_cidr_netmask=$(cat $cluster_config | y2j | jq -r .ipsec_partner.private[0].cidr_netmask)
    private_ip1_nic=$(cat $cluster_config | y2j | jq -r .ipsec_partner.private[0].nic)
    private_ip1_vnic_no=$(cat $cluster_config | y2j | jq -r .ipsec_partner.private[0].vnic_no)

    private_ip2=$(cat $cluster_config | y2j | jq -r .ipsec_partner.private[1].ip)
    private_ip2_cidr_netmask=$(cat $cluster_config | y2j | jq -r .ipsec_partner.private[1].cidr_netmask)
    private_ip2_nic=$(cat $cluster_config | y2j | jq -r .ipsec_partner.private[1].nic)
    private_ip2_vnic_no=$(cat $cluster_config | y2j | jq -r .ipsec_partner.private[1].vnic_no)

    route1_destination=$(cat $cluster_config | y2j | jq -r .ipsec_partner.route[0].destination)
    route1_device=$(cat $cluster_config | y2j | jq -r .ipsec_partner.route[0].device)
    route1_gateway=$(cat $cluster_config | y2j | jq -r .ipsec_partner.route[0].gateway)
    route1_src=$(cat $cluster_config | y2j | jq -r .ipsec_partner.route[0].src)
    if [ "$route1_src" == IFADDR ]; then
        route1_src=$(getPrimaryIp $route1_device)
    fi

    route2_destination=$(cat $cluster_config | y2j | jq -r .ipsec_partner.route[1].destination)
    route2_device=$(cat $cluster_config | y2j | jq -r .ipsec_partner.route[1].device)
    route2_gateway=$(cat $cluster_config | y2j | jq -r .ipsec_partner.route[1].gateway)
    route2_src=$(cat $cluster_config | y2j | jq -r .ipsec_partner.route[1].src)
    if [ "$route2_src" == IFADDR ]; then
        route2_src=$(getPrimaryIp $route2_device)
    fi

    libreswan_service=$(cat $cluster_config | y2j | jq -r .ipsec_partner.libreswan_service)
}
getConfiguration

#
# configure pacemaker for configure Libreswan cluster
#

#
# check if root
#
if [ "$(whoami)" != 'root' ]; then
    echo "Error. You must be root to install pacemaker."
    exit 1
fi

#
# clear all constrains
#
for cons in $(pcs constraint list --full | cut -d: -f3 | cut -f1 -d')'); do
    pcs constraint remove $cons
done
pcs constraint list --full

#
# delete all resource
#
# regexp to decide pcs resource \s*(\w+)\s+\(([\w:]+)\):\s+(\w+)\s+([\w-]+)
for resource in $(pcs resource show | tr -d '[ \t]' | cut -f1 -d'('); do    
    pcs resource delete $resource
done

#
# configure Libreswan cluster
#

echo ==============================
echo ipsec_cluster_routing_no1
echo ==============================
getConfiguration
echo destination=$route1_destination
echo device=$route1_device
echo gateway=$route1_gateway
echo src=$route1_src
pcs resource delete ipsec_cluster_routing_no1
pcs resource create ipsec_cluster_routing_no1 \
    ocf:heartbeat:Route \
    destination=$route1_destination \
    device=$route1_device \
    gateway=$route1_gateway \
    op monitor interval=60s timeout="15s" \
    op start interval="0" timeout="15s" \
    op stop interval="0" timeout="15s"
#!!! source canot be taken from cfg as is diffetent on each node!

echo ==============================
echo ipsec_cluster_routing_no2
echo ==============================
getConfiguration
echo destination=$route2_destination
echo device=$route2_device
echo gateway=$route2_gateway
echo src=$route2_src
pcs resource delete ipsec_cluster_routing_no2
pcs resource create ipsec_cluster_routing_no2 \
    ocf:heartbeat:Route \
    destination=$route2_destination \
    device=$route2_device \
    gateway=$route2_gateway \
    op monitor interval=60s timeout="15s" \
    op start interval="0" timeout="15s" \
    op stop interval="0" timeout="15s"
#!!! source canot be taken from cfg as is diffetent on each node!


echo ==============================
echo ipsec_cluster_inet_ip_no1
echo ==============================
getConfiguration
echo nic=$private_ip2_nic
echo ip=$private_ip2
echo cidr_netmask=$private_ip2_cidr_netmask
getConfiguration
pcs resource delete ipsec_cluster_inet_ip_no1
pcs resource create ipsec_cluster_inet_ip_no1 \
    ocf:heartbeat:IPaddr2 \
    nic=$private_ip2_nic \
    ip=$private_ip2 \
    cidr_netmask=$private_ip2_cidr_netmask \
    op monitor interval=30s timeout="5s" \
    op start interval="0" timeout="5s" \
    op stop interval="0" timeout="5s"

echo ==============================
echo ipsec_cluster_inet_ip_no2
echo ==============================
getConfiguration
echo nic=$private_ip1_nic
echo ip=$private_ip1
echo cidr_netmask=$private_ip1_cidr_netmask
pcs resource delete ipsec_cluster_inet_ip_no2
pcs resource create ipsec_cluster_inet_ip_no2 \
    ocf:heartbeat:IPaddr2 \
    nic=$private_ip1_nic \
    ip=$private_ip1 \
    cidr_netmask=$private_ip1_cidr_netmask \
    op monitor interval=30s timeout="5s" \
    op start interval="0" timeout="5s" \
    op stop interval="0" timeout="5s"


echo ==============================
echo ipsec_cluster_private_ip_no1
echo ==============================
getConfiguration
echo ip=$private_ip2
echo vnic_no=$private_ip2_vnic_no
pcs resource delete ipsec_cluster_private_ip_no1
pcs resource create ipsec_cluster_private_ip_no1 \
    ocf:heartbeat:oci_privateip \
    ip=$private_ip2 \
    vnic_no=$private_ip2_vnic_no \
    op monitor interval=60s timeout="30s" \
    op start interval="0" timeout="30s" \
    op stop interval="0" timeout="30s"

echo ==============================
echo ipsec_cluster_private_ip_no2
echo ==============================
getConfiguration
echo ip=$private_ip1
echo vnic_no=$private_ip1_vnic_no
pcs resource delete ipsec_cluster_private_ip_no2
pcs resource create ipsec_cluster_private_ip_no2 \
    ocf:heartbeat:oci_privateip \
    ip=$private_ip1 \
    vnic_no=$private_ip1_vnic_no \
    op monitor interval=60s timeout="30s" \
    op start interval="0" timeout="30s" \
    op stop interval="0" timeout="30s"


echo ==============================
echo ipsec_cluster_public_ip
echo ==============================
getConfiguration
echo publicIp=$public_ip
echo publicIp_id=$public_ip_oicd
echo vnic_no=$public_ip_vnic_no
pcs resource delete ipsec_cluster_public_ip
pcs resource create ipsec_cluster_public_ip \
    ocf:heartbeat:oci_publicip \
    publicIp=$public_ip \
    publicIp_id=$public_ip_oicd \
    vnic_no=$public_ip_vnic_no \
    op monitor interval=60s timeout="30s" \
    op start interval="0" timeout="30s" \
    op stop interval="0" timeout="30s"

echo ==============================
echo systemd:$libreswan_service
echo ==============================
getConfiguration
echo systemd:$libreswan_service
pcs resource delete ipsec_cluster_libreswan systemd:$libreswan_service
pcs resource create ipsec_cluster_libreswan systemd:$libreswan_service \
    op monitor interval="60s" timeout="15s" \
    op start interval="0" timeout="15s" \
    op stop interval="0" timeout="15s"


#
# keep right order of starting resources
#
echo ==============================
echo ordering
echo ==============================


# routes are the most important | having both assign public ip
pcs constraint order ipsec_cluster_routing_no1 then ipsec_cluster_routing_no2
pcs constraint order ipsec_cluster_routing_no2 then ipsec_cluster_public_ip

# libreswan having public ip
pcs constraint order ipsec_cluster_public_ip then ipsec_cluster_libreswan

# enable first gateway/routing having libreswan
pcs constraint order ipsec_cluster_libreswan then ipsec_cluster_inet_ip_no1
pcs constraint order ipsec_cluster_libreswan then ipsec_cluster_private_ip_no1

# enable second gateway/routing having libreswan
pcs constraint order ipsec_cluster_libreswan then ipsec_cluster_inet_ip_no2
pcs constraint order ipsec_cluster_libreswan then ipsec_cluster_private_ip_no2


#
# keep resources together
#
echo ==============================
echo colocation
echo ==============================

# public ip needs routing (to access OCI API)
pcs constraint colocation add ipsec_cluster_public_ip with ipsec_cluster_routing_no1 score=INFINITY
pcs constraint colocation add ipsec_cluster_public_ip with ipsec_cluster_routing_no2 score=INFINITY

# libreswan needs public ip
pcs constraint colocation add ipsec_cluster_libreswan with ipsec_cluster_public_ip score=INFINITY

# libreswan needs both private gateway ip addresses
pcs constraint colocation add ipsec_cluster_libreswan with ipsec_cluster_inet_ip_no1 score=INFINITY
pcs constraint colocation add ipsec_cluster_libreswan with ipsec_cluster_inet_ip_no2 score=INFINITY

# each gateway ip needs own OCI private ip
pcs constraint colocation add ipsec_cluster_inet_ip_no1 with ipsec_cluster_private_ip_no1 score=INFINITY
pcs constraint colocation add ipsec_cluster_inet_ip_no2 with ipsec_cluster_private_ip_no2 score=INFINITY


#
# report status
#
echo ==============================
echo status
echo ==============================
pcs constraint list --full
pcs status

#
# summary
#
if [ ! -z "$libreswan_service" ]; then
    echo "Floating ip cluster ready."
else
    echo "Libreswan cluster ready."
fi
echo "Done."
