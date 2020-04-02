#!/bin/bash
action=$1

#
# http://www.linux-ha.org/doc/dev-guides/ra-dev-guide.html
#

# Initialization:
: ${OCF_FUNCTIONS_DIR=${OCF_ROOT}/lib/heartbeat}
. ${OCF_FUNCTIONS_DIR}/ocf-shellfuncs

DEBUG=1

export LC_ALL=en_US.utf8
export LANG=en_US.utf8
export LC_CTYPE=en_US.utf8


#
# functions
#

# date
function utc::now() {
    #date +'%d%m%YT%H%M'
    date -u +"%Y-%m-%dT%H:%M:%S.000Z"
}

# logging
function loginfo {
    line_pfx="$(utc::now)"
    echo "$line_pfx;$1" >> /var/log/oci_publicip_$OCF_RESKEY_vnic_no.log
}

function logdebug {
    if [ $DEBUG -eq 1 ];then
        line_pfx="$(utc::now)"
        echo "$line_pfx;$1" >> /var/log/oci_publicip_$OCF_RESKEY_vnic_no.log
    fi
}

# function getVNICIp_id() {
#     vnic_no=$1

#     call_id=private_ip_curl
#     timeout 5 curl -s -L http://169.254.169.254/opc/v1/vnics/ > /run/oci/$call_id.out 2> /run/oci/$call_id.err
#     if [ $? -ne 0 ]; then
#         loginfo "getVNICIp_id: Error. $(cat /run/oci/$call_id.out), $(cat /run/oci/$call_id.err)"
#         return 1
#     else
#         loginfo "getVNICIp_id: OK. $(cat /run/oci/$call_id.out), $(cat /run/oci/$call_id.err)"
#         vnic_id=$(cat /run/oci/$call_id.out | jq -r .[$vnic_no].vnicId)
#     fi

#     call_id=private_ip_list
#     timeout 5 oci network private-ip list --vnic-id $vnic_id > /run/oci/$call_id.out 2> /run/oci/$call_id.err
#     if [ $? -ne 0 ]; then
#         loginfo "getVNICIp_id: Error. $(cat /run/oci/$call_id.out), $(cat /run/oci/$call_id.err)"
#         return 1
#     else
#         privateIp_id=$(cat /run/oci/$call_id.out | 
#         sed 's/is-primary/is_primary/g' | 
#         jq -r '.data[] | select(.is_primary == true) | .id')
#         loginfo "getVNICIp_id: OK. $(cat /run/oci/$call_id.out), $(cat /run/oci/$call_id.err)"
#     fi

#     echo $privateIp_id
# }

# function getPublicIp_id() {
#     publicIp_id=$1

#     call_id=public_ip_get
#     timeout 5 oci network public-ip get --public-ip-address  $publicIp_id >/run/oci/$call_id.out 2> /run/oci/$call_id.err
#     if [ $? -ne 0 ]; then
#         loginfo "getPublicIp_id: Error. $(cat /run/oci/$call_id.out), $(cat /run/oci/$call_id.err)"
#         return 1
#     fi

#     cat /run/oci/$call_id.out | jq -r .data.id
# }

function hasPublicIp() {

    logdebug "hasPublicIp: public-ip get started"
    timeout 5 oci network public-ip get --public-ip-address $OCF_RESKEY_publicIp > /run/oci/public_ip_get.json 2>/run/oci/public_ip_get.err
    result=$?
    if [ $result -eq 0 ]; then
        logdebug "hasPublicIp: looking for entity_type"
        entity_type=$(cat /run/oci/public_ip_get.json | sed 's/assigned-entity-type/assigned_entity_type/g' | jq -r '.data.assigned_entity_type')

        case $entity_type in
        PRIVATE_IP)
            entity_id=$(cat /run/oci/public_ip_get.json | sed 's/assigned-entity-id/assigned_entity_id/g' | jq -r '.data.assigned_entity_id')

            # so here we have private ip OCID
            if [ "$entity_id" == "$OCF_RESKEY_privateIP_vnic_id" ]; then
                logdebug "hasPublicIp: OK. Response: $(cat /run/oci/public_ip_get.json), $(cat /run/oci/public_ip_get.err)"
                return 0
            else
                logdebug "hasPublicIp: Assigned to other. Response: $(cat /run/oci/public_ip_get.json), $(cat /run/oci/public_ip_get.err)"
                return 1
            fi
            ;;
        null)
            logdebug "hasPublicIp: Not assigned. Response: $(cat /run/oci/public_ip_get.json), $(cat /run/oci/public_ip_get.err)"
            return 1
            ;;
        *)
            logdebug "hasPublicIp: Error. Not supported entity_type reported. Response: $(cat /run/oci/public_ip_get.json), $(cat /run/oci/public_ip_get.err)"
            return 1
            ;;
        esac
        logdebug "hasPublicIp: entity_type processed"
    else
        logdebug "hasPublicIp: General error. Response: $(cat /run/oci/public_ip_get.json), $(cat /run/oci/public_ip_get.err)"
        return 1
    fi
}

function meta_data() {
    cat <<EOF
<?xml version="1.0"?>
<!DOCTYPE resource-agent SYSTEM "ra-api-1.dtd">
<resource-agent name="oci_public_ip" version="0.1">
  <version>0.1</version>
  <longdesc lang="en">
  Assigns the specified public IP to a netowrk card.
  
  More info: https://docs.cloud.oracle.com/en-us/iaas/tools/oci-cli/2.9.2/oci_cli_docs/cmdref/network/public-ip/update.html
  </longdesc>
  <shortdesc lang="en">Assign PublicIp via Oracle OCI API</shortdesc>

<parameters>

<parameter name="publicIp" unique="0" required="1">
<longdesc lang="en">
Reserved public IP address created in OCI.
</longdesc>
<shortdesc lang="en">publicIp</shortdesc>
</parameter>

<parameter name="publicIp_id" unique="0" required="1">
<longdesc lang="en">
OCID of reserved public IP address.
</longdesc>
<shortdesc lang="en">publicIp_id</shortdesc>
</parameter>

<parameter name="privateIP_id" unique="0" required="1">
<longdesc lang="en">
OCID of PrivateIP_id attached to VNIC.
</longdesc>
<shortdesc lang="en">privateIP_id</shortdesc>
</parameter>

<parameter name="privateIP_vnic_id" unique="0" required="1">
<longdesc lang="en">
OCID of VNIC with attached PrivateIP.
</longdesc>
<shortdesc lang="en">privateIP_vnic_id</shortdesc>
</parameter>

</parameters>

  <actions>
    <action name="start"        timeout="20" />
    <action name="stop"         timeout="20" />
    <action name="monitor"      timeout="20" interval="10" depth="0" />
    <action name="meta-data"    timeout="5" />
  </actions>

</resource-agent>
EOF
}

umask 077
mkdir -p /run/oci

if [ ! "$action" == "meta-data" ]; then 
    loginfo "oci_public_ip: Initializing: $action, $OCF_RESKEY_publicIp, 
    $OCF_RESKEY_publicIp_id, $OCF_RESKEY_privateIP_id, $OCF_RESKEY_privateIP_vnic_id"
fi

case $action in
start)
    if hasPublicIp; then
        result=$OCF_SUCCESS
    else
        call_id=rm_start_public_ip_get
        timeout 5 oci network public-ip update \
        --public-ip-id $OCF_RESKEY_publicIp_id \
        --private-ip-id $OCF_RESKEY_privateIP_id \
        --force >/run/oci/$call_id.out 2> /run/oci/$call_id.err
        if [ $? -ne 0 ]; then
            loginfo "rm_start: Error. $(cat /run/oci/$call_id.out), $(cat /run/oci/$call_id.err)"
            result=$OCF_ERR_GENERIC
        else
            loginfo "rm_start: Assigned. $(cat /run/oci/$call_id.out), $(cat /run/oci/$call_id.err)"
            result=$OCF_SUCCESS
        fi
    fi
    ;;
stop)
    #
    # IGNORE STOP! ALWAYS RETURN SUCCESS.
    #
    # if hasPublicIp $OCF_RESKEY_publicIp; then

    #     call_id=rm_stop_public_ip_get
    #     timeout 5 oci network public-ip update \
    #     --public-ip-id $oci_publicIp_id \
    #     --private-ip-id '' >/run/oci/$call_id.out 2> /run/oci/$call_id.err
    #     if [ $? -ne 0 ]; then
    #         loginfo "rm_stop: Error. $(cat /run/oci/$call_id.out), $(cat /run/oci/$call_id.err)"
    #         result=$OCF_ERR_GENERIC
    #     else
    #         loginfo "rm_stop: Unassigned. $(cat /run/oci/$call_id.out), $(cat /run/oci/$call_id.err)"
    #         result=$OCF_SUCCESS
    #     fi
    # fi
    result=$OCF_SUCCESS
    ;;
meta-data)
    meta_data
    result=$OCF_SUCCESS
    ;;
status | monitor)
    # resource parameters
    # http://www.linux-ha.org/doc/dev-guides/_api_definitions.html#_environment_variables
    if hasPublicIp; then
        result=$OCF_SUCCESS
    else
        result=$OCF_NOT_RUNNING
    fi
    ;;
*)
    loginfo "No such action: $action"
    result=$OCF_ERR_UNIMPLEMENTED
    ;;
esac
rc=$result

ocf_log debug "${OCF_RESOURCE_INSTANCE} $action returned $rc"
exit $rc
