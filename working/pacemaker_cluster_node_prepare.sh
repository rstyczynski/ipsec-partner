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
pass=$(cat $cluster_config | y2j | jq -r .ipsec_partner.cluster.pass)XX

#
# check if root
#
if [ "$(whoami)" != 'root' ]; then
    echo "Error. You must be root to install pacemaker."
    exit 1
fi

#
# install required software
#
yum install -y pacemaker pcs resource-agents git jq libreswan

function getOCIresoures() {
    if [ ! -d ipsec-partner ]; then
    git clone https://github.com/rstyczynski/ipsec-partner.git
    else
    cd ipsec-partner
    git pull
    cd ..
    fi
    \cp -f ipsec-partner/working/oci_privateip.sh /usr/lib/ocf/resource.d/heartbeat/oci_privateip
    \cp -f ipsec-partner/working/oci_publicip.sh /usr/lib/ocf/resource.d/heartbeat/oci_publicip
    chmod +x /usr/lib/ocf/resource.d/heartbeat/oci_privateip
    chmod +x /usr/lib/ocf/resource.d/heartbeat/oci_publicip
}
getOCIresoures

#
# configure firewall
#
firewall-cmd --permanent --add-service=high-availability
firewall-cmd --add-service=high-availability

#
# start deamon
#
systemctl start pcsd.service
systemctl enable pcsd.service

#
# specify password for cluster user
#
bash -c "echo \"$pass\" | passwd --stdin hacluster"

#
# stop ipsec for boot time and now
#
systemctl stop ipsec.service
systemctl disable ipsec.service

#
# done
#
echo "Cluster node configured."
echo "Done."


