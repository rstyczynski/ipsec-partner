#!/bin/bash

#set -x

# set ipsec-partner environment, including Oracle OCI client libraries
PATH=$PATH:/opt/ipsec-partner/sbin:/opt/ipsec-partner/bin
source $HOME/.bash_profile

#####
##### parameter seciton start
#####

function usage() {
    echo -n "Usage: $(basename $0) "
    cat $0 | grep -v '/# parameters - start/,/# parameters - stop/p' |
        sed -n '/# parameters - start/,/# parameters - stop/p' |
        grep '\--' | cut -f1 -d ')' | tr -s ' ' | tr '\n' ' '
    echo

    echo
    echo "Mandatory parameters: "
    cat $0 | grep -v '/# mandatory parameters - start/,/# mandatory parameters - stop/p' |
        sed -n '/# mandatory parameters - start/,/# mandatory parameters - stop/p' |
        grep '\[ -z' | sed 's/|/;/g' | cut -f2 -d ';' | sed 's/"$//g' | nl
    echo

    echo
    echo "Parameter defaults: "
    cat $0 | grep -v '/# parameters defaults - start/,/# parameters defaults - stop/p' |
        sed -n '/# parameters defaults - start/,/# parameters defaults - stop/p' |
        grep '\[ -z' | sed 's/&& /;/g' | cut -f2 -d ';' | nl
    echo
}

# parameters - start
while [ $# -gt 0 ]; do
    opt="$1"
    shift
    case $opt in
    --ipsec-name) ipsec_name=$1 ;;
    --ipsec-id) ipsec_id=$1 ;;
    --tunnels) tunnels=$1 ;;
    --time_up) time_up=$1 ;;
    --time_down) time_down=$1 ;;
    --interval) interval=$1 ;;
    --timeout) oci_timeout=$1 ;;
    --tmp) tmpdirbase=$1 ;;
    --log) log=$1 ;;
    --debug) loginfo_trace_stdout=$1 ;;
    --compartment-id) compartment_id=$1 ;;
    --telemetry-endpoint) telemetry_endpoint=$1 ;;
    -h | --help)
        usage
        exit
        ;;
    esac
    shift
done
# parameters - stop

# parameters defaults - start
[ -z $compartment_id ] && compartment_id=$(curl -s http://169.254.169.254/opc/v1/instance/ | jq -r '.compartmentId')
[ -z $telemetry_endpoint ] && telemetry_endpoint="https://telemetry-ingestion.$(curl -s http://169.254.169.254/opc/v1/instance/ | jq -r '.region').oraclecloud.com"
[ -z $tunnels ] && tunnels=$(cat /etc/ipsec.d/partners/${ipsec_name}.cfg | grep 'ipsec_tunnel[0-9]_auto' | wc -l)
[ -z $ipsec_id ] && ipsec_id=$(cat /etc/ipsec.d/partners/${ipsec_name}.cfg | grep 'ipsec_id' | cut -f2 -d'=')
[ -z $interval ] && interval=60
[ -z $time_up ] && time_up=300
[ -z $time_down ] && time_down=300
[ -z $oci_timeout ] && oci_timeout=5
[ -z $tmpdirbase ] && tmpdirbase=/tmp/monitor_ipsec
[ -z $log ] && log=/var/log/ipsec_partner
# parameters defaults - stop

# mandatory parameters - start
error=''
[ -z $ipsec_name ] && error="$error|ipsec_name cannot be none"
[ -z $ipsec_id ] && error="$error|ipsec_id cannot be none"
[ -z $compartment_id ] && error="$error|compartment_id cannot be none"
[ -z $telemetry_endpoint ] && error="$error|telemetry_endpoint cannot be none"

if [ "$error" != "" ]; then
    echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
    echo -n "Error. Mandatory arguments missing:"
    echo "$error" | tr '|' '\n' | nl
    echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
    echo
    usage
    exit 1
fi
# mandatory parameters - stop

#####
##### parameter seciton stop
#####

# tmp
trap stop INT
tmp=$tmpdirbase/$$/$RANDOM
mkdir -p $tmp
function stop() {
    \rm $tmp/*
    \rm -rf $tmpdirbase/$$
}

# date
function utc::now() {
    #date +'%d%m%YT%H%M'
    date -u +"%Y-%m-%dT%H:%M:%S.000Z"
}

# store stdout stderr to log file
function configureLog() {

    while [ $# -gt 0 ]; do
        opt="$1"
        shift
        case $opt in
        --log_add_date) log_add_date=$1 ;;
        --log_suffix) log_suffix=$1 ;;
        esac
        shift
    done

    [ -z $log_add_date ] && log_add_date=NO
    [ -z $log_suffix ] && log_suffix=NO

    log_status=NA
    while [ "$log_status" != "OK" ]; do
        [ -d $log ] || mkdir -p $log 2>/dev/null
        touch $log/touch 2>/dev/null
        if [ $? -ne 0 ]; then
            echo -n "Log directory not available. Trying current directory..." >&2
            log="./log"
        else
            \rm $log/touch
            log_status=OK
            echo >&2 "Log configured."
        fi
    done

    script_pathname=$0
    script_name=$(basename $script_pathname)

    logfile=$log/$script_name

    if [ ! $log_suffix == NO ]; then
        logfile=${logfile}-$log_suffix
    fi

    if [ $log_add_date == YES ]; then
        date_str=$(utc::now)
        logfile=${logfile}-$date_str
    fi

    exec > >(tee -a ${logfile}.log)
    kill_on_exit=$!
    exec 2> >(tee -a ${logfile}.info >&2)
    kill_on_exit="$kill_on_exit $!"
    trap "stdbuf -oL printf ''; kill $kill_on_exit" EXIT
}

# logging
function loginfo() {

    line_pfx="$(utc::now)"

    loginfo_out=STDOUT
    loginfo_trace=NO
    if [ "$1" == "error" ]; then
        loginfo_out=STDERR
        shift
    elif [ "$1" == "trace" ]; then
        loginfo_trace=YES
        shift
    fi

    if [ "$loginfo_out" == "STDERR" ]; then
        echo >&2 "$line_pfx;$1"
    fi

    if [ "$loginfo_trace" == YES ]; then
        if [ "$loginfo_trace_stdout" == YES ]; then
            echo "$line_pfx;$1"
        fi
    else
        echo "$line_pfx;$1"
    fi
}

#
function assert_utilities() {
    required_cmd=$1

    cmd_missing=''
    for cmd in $required_cmd; do
        hash $cmd 2>/dev/null
        if [ $? -ne 0 ]; then
            cmd_missing="$cmd_missing $cmd"
        fi
    done

    if [ "$cmd_missing" != "" ]; then
        loginfo error "Error. Required utilities not available. Check PATH or install packages. Not reachable utilities: $cmd_missing"

        exit 2
    fi
}

function getInt() {
    if [ -z "$1" ]; then
        echo 0
    else
        echo $1
    fi
}
#
function oci_metric() {

    if [ "$1" == "set_file" ]; then
        oci_json_file=$2
        echo -n >$oci_json_file
        return
    fi

    if [ "$1" == "start_array" ]; then
        oci_json_array_started=YES
        echo '[' >>$oci_json_file
        return
    fi

    metric_name=$1
    metric_value=$2
    metric_unit=$3
    metric_more=$4

    if [ "$#" -ne 4 ]; then
        loginfo error "Error. oci_metric gets 4 mandatory parameters. Provided: $#: $1 $2 $3 $4"
    fi

    if [ -z $oci_json_file ]; then
        loginfo error "Error. oci_json_file not set. Use oci_metric set_file file first."
        return
    fi

    cat >>$oci_json_file <<EOF
        {
                "namespace": "custom_ipsec",
                "compartmentId": "$compartment_id",
                "name": "$metric_name",
EOF

    if [ "$metric_name" == "tunnel_status" ]; then
        cat >>$oci_json_file <<EOF
                "dimensions": { "tunnel_name": "${ipsec_name}" },
EOF
    else
        cat >>$oci_json_file <<EOF
                "dimensions": { "ipsec_name": "${ipsec_name}_tunnel${tunnel}" },
EOF
    fi

    cat >>$oci_json_file <<EOF
                "metadata": { "unit": "$metric_unit" },
                "datapoints": [
                    {
                        "timestamp": "$(utc::now)",
                        "value": $metric_value
                    }
                ]
            }
EOF

    if [ "$metric_more" == "expect_more" ]; then
        echo ', ' >>$oci_json_file
    else
        if [ "$oci_json_array_started" == "YES" ]; then
            echo ']' >>$oci_json_file
            unset oci_json_array_started
        fi
    fi
}

#
# prepare
#
configureLog --log_suffix $ipsec_name --log_add_date NO

assert_utilities "timeout date touch cat tr oci resource_state_filter.py"

#
# run
#

# check tunnel status
# ipsec channel is up when file with data is visible. Otherwise line is down.
updown='downup,updown,upup/downdown'
[ -f $tmp/ipsec_partner_status ] && \rm $tmp/ipsec_partner_status
for tunnel in $(seq 1 $tunnels); do
    if [ -f /run/ipsec-partner/status/ipsec/whack/${ipsec_name}_tunnel$tunnel ]; then
        echo -n up >>$tmp/ipsec_partner_status
    else
        echo -n down >>$tmp/ipsec_partner_status
    fi
done

# log
loginfo "Tunnels status: $(cat $tmp/ipsec_partner_status)"

# process tunnel state
[ ! -d /run/ipsec-partner/db ] && mkdir /run/ipsec-partner/db

cat $tmp/ipsec_partner_status |
    resource_state_filter.py \
        -r "$ipsec_name" -c "$updown" -d "$time_down" -u "$time_up" -p "/run/ipsec-partner/db" >$tmp/ipsec_partner_tunnels_status

# log
loginfo trace "$(cat $tmp/ipsec_partner_tunnels_status | jq -c '.')"

# get numeric value of current state
state_numeric=$(cat $tmp/ipsec_partner_tunnels_status | jq -r '.state_numeric')
if [ -z "$state_numeric" ]; then
    loginfo error "Error. Answer from resource_state_filter.py malformed."
fi

# cat $tmp/oci_tunnels_status | jq -r '.state'

# cat $tmp/oci_tunnels_status | jq -r '.alarm_raise'
# cat $tmp/oci_tunnels_status | jq -r '.alarm_dismiss'

# cat $tmp/oci_tunnels_status | jq -r '.flapping'
# cat $tmp/oci_tunnels_status | jq -r '.flapping_raise'
# cat $tmp/oci_tunnels_status | jq -r '.flapping_dismiss'

# set out file for JSON oci message and start main array
oci_metric set_file $tmp/ipsec_partner_smoothed_status.json
oci_metric start_array

# tunnel smoothed status
oci_metric tunnel_status $state_numeric level expect_more

# ipsec channel interface counters
#
if [ -f /run/ipsec-partner/status/ip/tunnel/tunnel ]; then

    for tunnel in $(seq 1 $tunnels); do

        # ipsec channel up/down
        #
        if [ -f /run/ipsec-partner/status/ipsec/whack/${ipsec_name}_tunnel$tunnel ]; then
            oci_metric ipsec_status 100 level expect_more
        else
            oci_metric ipsec_status 0 level expect_more
        fi

        if_name=vti$(($ipsec_id + $tunnel))

        #jq adds new line! 
        tx_data=$(cat /run/ipsec-partner/status/ip/tunnel/tunnel | jq -cj ".${if_name}.TX"  | tr -cd '[:print:]')
        if [ "$tx_data" != "null" ]; then
            loginfo "TX data: >$tx_data<"
            eval $(echo $tx_data |
                # {"Errors":285,"NoBufs":0,"Packets":4611915,"NoRoute":0,"Bytes":5493003169,"DeadLoop":0}
                sed 's/":/=/g' |
                # {"Errors=285,"NoBufs=0,"Packets=4611915,"NoRoute=0,"Bytes=5493003169,"DeadLoop=0}
                sed 's/,"/;/g' |
                # {"Errors=285;NoBufs=0;Packets=4611915;NoRoute=0;Bytes=5493003169;DeadLoop=0}
                sed 's/[{},"]//g' |
                # Errors=285;NoBufs=0;Packets=4611915;NoRoute=0;Bytes=5493003169;DeadLoop=0
                tr ';' '\n' |
                sed 's/^/TX_/g') # prefix with TX

            oci_metric TX_Packets $(getInt $TX_Packets) packet expect_more
            oci_metric TX_Bytes $(getInt $TX_Bytes) Byte expect_more
            oci_metric TX_Errors $(getInt $TX_Errors) occurance expect_more
            oci_metric TX_DeadLoop $(getInt $TX_DeadLoop) occurance expect_more
            oci_metric TX_NoRoute $(getInt $TX_NoRoute) occurance expect_more
            oci_metric TX_NoBufs $(getInt $TX_NoBufs) occurance expect_more

            unset TX_Packets TX_Bytes TX_Errors TX_DeadLoop TX_NoRoute TX_NoBufs

        fi

        rx_data=$(cat /run/ipsec-partner/status/ip/tunnel/tunnel | jq -cj ".${if_name}.RX" |  tr -cd '[:print:]')
        if [ "$rx_data" != "null" ]; then
            loginfo "RX data: >$rx_data<"
            eval $(echo $rx_data |
                # {"Errors":0,"CsumErrs":0,"Packets":5861329,"Bytes":5571272152,"Mcasts":0,"OutOfSeq":0}
                sed 's/":/=/g' |
                sed 's/,"/;/g' |
                sed 's/[{},"]//g' |
                tr ';' '\n' |
                sed 's/^/RX_/g') # prefix with RX

            oci_metric RX_Packets $(getInt $RX_Packets) packet expect_more
            oci_metric RX_Bytes $(getInt $RX_Bytes) Byte expect_more
            oci_metric RX_Errors $(getInt $RX_Errors) occurance expect_more
            oci_metric RX_CsumErrs $(getInt $RX_CsumErrs) occurance expect_more
            oci_metric RX_OutOfSeq $(getInt $RX_OutOfSeq) occurance expect_more

            unset RX_Packets RX_Bytes RX_Errors RX_CsumErrs RX_OutOfSeq RX_Mcasts

        fi

        if [ $tunnel -lt $tunnels ]; then
            oci_metric RX_Mcasts $(getInt $RX_Mcasts) occurance expect_more
        else
            oci_metric RX_Mcasts $(getInt $RX_Mcasts) occurance no_more
        fi

    done

    # log
    loginfo trace "OCI request: $(cat $oci_json_file | jq -c '.')"

    # post data to OCI telemetry
    timeout $oci_timeout oci monitoring metric-data post --metric-data file://$oci_json_file \
        --endpoint $telemetry_endpoint | jq -c '.' >$tmp/metric_post_status.json
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        loginfo error "Error. Posting data to OCI failed."
    else
        loginfo "Reported to OCI telemetry."
    fi

    # log
    loginfo trace "OCI response: $(cat $tmp/metric_post_status.json)"

else

    loginfo error "Warning. Tunnel data file not found. Expected /run/ipsec-partner/status/ip/tunnel/tunnel "
fi

# exit
stop
exit
