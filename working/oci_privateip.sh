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
    echo "$line_pfx;$1" >> /var/log/oci_privateip_$OCF_RESKEY_vnic_no.log
}

function logdebug {
    if [ $DEBUG -eq 1 ];then
        line_pfx="$(utc::now)"
        echo "$line_pfx;$1" >> /var/log/oci_privateip_$OCF_RESKEY_vnic_no.log
    fi
}


function hasPrivateIp() {
    oci_private_ip=$1
    oci_vnic_id=$2

    if [ ! -f /run/oci/private_ip.text ]; then
        logdebug "hasPrivateIp: Not started"
        return 1
    else
        privateip_id=$(cat /run/oci/private_ip.text)

        # I do not want to cal OCI API too frequently
        # anyway is started returning:
        # ServiceError:
        # {
        #     "code": "NotAuthorizedOrNotFound", 
        #     "message": "Either Floating Private IP with ID 10.106.6.251 does not exist or you are not authorized to access it.", 
        #     "opc-request-id": "8959A789DB594AC4AE463A248B668B39/3477B5A66D550CDF82E6DD75CFB969C7/263413879E35082A03FAF1BB25EC3310", 
        #     "status": 404
        # }
        # oci network private-ip get --private-ip-id $privateip_id > /run/oci/private_ip_get.json 2>/run/oci/private_ip_get.err
        # assigned_vnic_id=$(cat /run/oci/private_ip_get.json | jq -r '.data["vnic-id"]')
        # if [ "$assigned_vnic_id" == "$oci_vnic_id" ]; then
        #     return 0
        # else
        #     return 1
        # fi

        # let's use assign  w/o force option
        oci network vnic assign-private-ip \
                --vnic-id $oci_vnic_id \
                --ip-address $oci_private_ip > /run/oci/private_ip_gentleassign.json 2>/run/oci/private_ip_gentleassign.err
        if [ $? -eq 0 ] ; then
            if [ $(stat -c%s /run/oci/private_ip_gentleassign.err) -gt 0 ]; then

                grep "Taking no action as IP address $oci_private_ip is already assigned to VNIC $oci_vnic_id" /run/oci/private_ip_gentleassign.err >/dev/nul 2>&1
                if [ $? -eq 0 ]; then 
                    logdebug "hasPrivateIp: Already assigned. Response: $(cat /run/oci/private_ip_gentleassign.json), $(cat /run/oci/private_ip_gentleassign.err)"
                    return 0
                else

                    logdebug "hasPrivateIp: Error. Response: $(cat /run/oci/private_ip_gentleassign.json), $(cat /run/oci/private_ip_gentleassign.err)"
                    return 1
                fi
            else
                logdebug "hasPrivateIp: OK. Response: $(cat /run/oci/private_ip_gentleassign.json), $(cat /run/oci/private_ip_gentleassign.err)"
                return 0
            fi
        else
            logdebug "hasPrivateIp: Error. Response: $(cat /run/oci/private_ip_gentleassign.json), $(cat /run/oci/private_ip_gentleassign.err)"
            return 1
        fi

        # I can always ping assigned IP, even if it's unassigned from OCI side
        # ping $privateip_id always works ! :(

        # Let's set source IP to $privateip_id and try to cal external service. 
        # As we are insode of Oracle data center, let's ping oracle.com, but with only one jump
        # timeout 5 traceroute -s $privateip_id -m  1 oracle.com 2>&1 >/run/oci/hasPrivateIp.out
        # case $? in
        # 0)  # all good
        #     logdebug "hasPrivateIp: OK. Response: $(/run/oci/hasPrivateIp.out)"
        #     return 0 ;;
        # 1)  # no IP at the interfaces!
        #     logdebug "hasPrivateIp: No IP at the interfaces! Response: $(cat /run/oci/hasPrivateIp.out)"
        #     return 1 ;;
        # 124) # assigned IP at OS, but not at OCI or total error.
        #     logdebug "hasPrivateIp: assigned IP at OS, but not at OCI or total error. Response: $(cat /run/oci/hasPrivateIp.out)"
        #     return 1 ;;
        # esac  
    fi
}

function meta_data() {
    cat <<EOF
<?xml version="1.0"?>
<!DOCTYPE resource-agent SYSTEM "ra-api-1.dtd">
<resource-agent name="oci_private_ip" version="0.1">
  <version>0.1</version>
  <longdesc lang="en">Assigns a secondary private IP address to the specified VNIC. The secondary private IP must be in the same subnet as the VNIC. This command can also be used to move an existing secondary private IP to the specified VNIC.</longdesc>
  <shortdesc lang="en">Assign PrivateIp via Oracle OCI API</shortdesc>

<parameters>

<parameter name="ip" unique="0" required="1">
<longdesc lang="en">
A private IP address of your choice. Must be an available IP address within the subnet's CIDR. If you don't specify a value, Oracle automatically assigns a private IP address from the subnet.

More info: https://docs.cloud.oracle.com/en-us/iaas/tools/oci-cli/2.9.5/oci_cli_docs/cmdref/network/vnic/assign-private-ip.html
</longdesc>

<shortdesc lang="en">Private IP</shortdesc>
</parameter>

<parameter name="vnic_no" unique="0" required="1">
<longdesc lang="en">
The number of the VNIC on the host to assign the private IP to. The VNIC and private IP must be in the same subnet.
</longdesc>
<shortdesc lang="en">VNIC number on the host</shortdesc>
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
    loginfo "oci_privateip: Initializing: $action, $OCF_RESKEY_ip, $OCF_RESKEY_vnic_no"
    # moved to start, as it's not changing
    vnic_id=$(curl -s -L http://169.254.169.254/opc/v1/vnics/ | jq -r .[$OCF_RESKEY_vnic_no].vnicId)
    loginfo "oci_privateip: Initialized for: $OCF_RESKEY_ip on $vnic_id"
fi

echo $OCF_RESKEY_ip >/run/oci/private_ip.text

case $action in

start)
    if hasPrivateIp $OCF_RESKEY_ip $vnic_id; then
        result=$OCF_SUCCESS
    else
        # resource parameters
        # http://www.linux-ha.org/doc/dev-guides/_api_definitions.html#_environment_variables
        timeout 15 oci network vnic assign-private-ip \
            --vnic-id $vnic_id \
            --unassign-if-already-assigned \
            --ip-address $OCF_RESKEY_ip > /run/oci/private_ip_assign.json 2>/run/oci/private_ip_assign.err
        if [ $? -eq 0 ] ; then
            # when already assigned responses with null on stdout, and info on stderr and ecode 0. O means ok. Keep IP
            echo $OCF_RESKEY_ip >/run/oci/private_ip.text
            result=$OCF_SUCCESS
            loginfo "oci_privateip: started OK: $result, $(cat /run/oci/private_ip_assign.json), $(cat /run/oci/private_ip_assign.err)"
        else
            result=$OCF_ERR_GENERIC
            loginfo "oci_privateip: started with error: $result, $(cat /run/oci/private_ip_assign.json), $(cat /run/oci/private_ip_assign.err)"
        fi
    fi
    ;;
stop)
    # if hasPrivateIp $OCF_RESKEY_ip $vnic_id; then
    #     # resource parameters
    #     # http://www.linux-ha.org/doc/dev-guides/_api_definitions.html#_environment_variables
    #
    # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    # NEVER DETACH IP! It will be lost, next time you will attach it will be with different IP!
    # ALWAYS RETURN OK
    # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    #
    #     timeout 15 oci network vnic unassign-private-ip \
    #         --vnic-id $vnic_id \
    #         --ip-address $OCF_RESKEY_ip > /run/oci/private_ip_unassign.json 2>/run/oci/private_ip_unassign.err
    #     if [ $? -eq 0 ] ; then
    #         \rm -f /run/oci/private_ip_assign.json
    #         result=$OCF_SUCCESS
    #         loginfo "oci_privateip: stopped OK: $result, $(cat /run/oci/private_ip_unassign.json), $(cat /run/oci/private_ip_unassign.err)"
    #     else
    #         result=$OCF_ERR_GENERIC
    #         loginfo "oci_privateip: stopped with error: $result, $(cat /run/oci/private_ip_unassign.json), $(cat /run/oci/private_ip_unassign.err)"
    #     fi
    # fi
    result=$OCF_SUCCESS
    loginfo "oci_privateip: Stop OK"
    ;;
meta-data)
    meta_data
    result=$OCF_SUCCESS
    ;;
status | monitor)
    # resource parameters
    # http://www.linux-ha.org/doc/dev-guides/_api_definitions.html#_environment_variables
    if hasPrivateIp $OCF_RESKEY_ip $vnic_id; then
        result=$OCF_SUCCESS
        loginfo "oci_privateip: monitor OK"
    else
        result=$OCF_NOT_RUNNING
        loginfo "oci_privateip: monitor NOT RUNNING"
    fi
    ;;
*)
    logdebug "No such action: $action"
    result=$OCF_ERR_UNIMPLEMENTED
    ;;
esac
rc=$result

ocf_log debug "${OCF_RESOURCE_INSTANCE} $action returned $rc"
exit $rc
