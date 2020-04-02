#!/bin/bash



cluster_config=$1

# 
# functions
#
function j2y {
   ruby -ryaml -rjson -e 'puts YAML.dump(JSON.parse(STDIN.read))'
}

function y2j {
   ruby -ryaml -rjson -e 'puts JSON.dump(YAML.load(STDIN.read))'
}

#
# get parameters
#
cluster_nodes=$(cat $cluster_config | y2j | jq -r .ipsec_partner.cluster.nodes[])
pass=$(cat $cluster_config | y2j | jq -r .ipsec_partner.cluster.pass)

public_ip=$(cat $cluster_config | y2j | jq -r .ipsec_partner.public.ip)
public_ip_vnic_no=$(cat $cluster_config | y2j | jq -r .ipsec_partner.public.vnic_no)
public_ip_oicd=$(cat $cluster_config | y2j | jq -r .ipsec_partner.public.oicd)

private_ip=$(cat $cluster_config | y2j | jq -r .ipsec_partner.private[0].ip)
private_ip_cidr_netmask=$(cat $cluster_config | y2j | jq -r .ipsec_partner.private[0].cidr_netmask)
private_ip_nic=$(cat $cluster_config | y2j | jq -r .ipsec_partner.private[0].nic)
private_ip_vnic_no=$(cat $cluster_config | y2j | jq -r .ipsec_partner.private[0].vnic_no)

route_destination=$(cat $cluster_config | y2j | jq -r .ipsec_partner.route.destination)
route_device=$(cat $cluster_config | y2j | jq -r .ipsec_partner.route.device)
route_gateway=$(cat $cluster_config | y2j | jq -r .ipsec_partner.route.gateway)

libreswan_service=$(cat $cluster_config | y2j | jq -r .ipsec_partner.libreswan_service)


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
# configure Libreswan cluster
#


pcs resource create ipsec_cluster_private_ip \
ocf:heartbeat:oci_privateip \
ip=$private_ip \
vnic_no=$private_ip_vnic_no \
op monitor interval=60s timeout="30s"  \
op start interval="0" timeout="30s"  \
op stop interval="0" timeout="30s"

pcs resource create ipsec_cluster_inet_ip  \
ocf:heartbeat:IPaddr2 \
nic=$private_ip_nic \
ip=$private_ip \
cidr_netmask=$private_ip_cidr_netmask \
op monitor interval=30s timeout="5s" \
op start interval="0" timeout="5s" \
op stop interval="0" timeout="5s"

pcs resource create ipsec_cluster_public_ip  \
ocf:heartbeat:oci_publicip \
publicIp=$public_ip \
publicIp_id=$public_ip_oicd \
vnic_no=$public_ip_vnic_no \
op monitor interval=60s timeout="30s" \
op start interval="0" timeout="30s" \
op stop interval="0" timeout="30s"

pcs resource create ipsec_cluster_routing  \
ocf:heartbeat:Route \
destination=$route_destination \
device=$route_device \
gateway=$route_gateway \
op monitor interval=60s timeout="5s" \
op start interval="0" timeout="5s" \
op stop interval="0" timeout="5s"

if [ ! "null" == "$libreswan_service" ]; then
    systemctl stop ipsec
    systemctl disable ipsec
    pcs resource create ipsec_cluster_libreswan systemd:$libreswan_service \
    op monitor interval="60s" timeout="15s" \
    op start interval="0" timeout="15s" \
    op stop interval="0" timeout="15s"
fi

# keep right order of starting resources
pcs constraint order ipsec_cluster_inet_ip then ipsec_cluster_private_ip
pcs constraint order ipsec_cluster_private_ip then ipsec_cluster_public_ip
pcs constraint order ipsec_cluster_public_ip then ipsec_cluster_routing
if [ ! "null" == "$libreswan_service" ]; then 
    pcs constraint order ipsec_cluster_routing then ipsec_cluster_libreswan
fi

# keep resources together
pcs constraint colocation add ipsec_cluster_private_ip with ipsec_cluster_inet_ip score=INFINITY
pcs constraint colocation add ipsec_cluster_inet_ip with ipsec_cluster_public_ip score=INFINITY
pcs constraint colocation add ipsec_cluster_public_ip with ipsec_cluster_routing score=INFINITY
if [ ! "null" == "$libreswan_service" ]; then 
    pcs constraint colocation add ipsec_cluster_routing with ipsec_cluster_libreswan score=INFINITY
fi

#
# report status
#
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
