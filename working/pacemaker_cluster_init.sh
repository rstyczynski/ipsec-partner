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

#
# check if root
#
if [ "$(whoami)" != 'root' ]; then
    echo "Error. You must be root to install pacemaker."
    exit 1
fi

#
# configure pacemaker infrastructure
#
pcs cluster auth $cluster_nodes -u hacluster -p $pass --force

pcs cluster setup --force --name ipsec_cluster $cluster_nodes
pcs cluster start --all

pcs status

echo "Cluster nodes ready."
echo "Done."
