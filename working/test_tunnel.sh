


function down_ipsec {
    partner_name=$1
    tunnel_no=$2

    echo '============================'
    echo ' Tunnel DOWN'
    echo '============================'
    ipsec auto --down ${partner_name}_tunnel${tunnel_no}
    if [ $? -ne 0 ]; then
        echo 
        echo ' FAILED'
        echo '===================================='
        return 1
    else
        echo
        echo '===================================='
        echo ' OK'
        echo '===================================='
        return 0
    fi
}

function up_ipsec {
    partner_name=$1
    tunnel_no=$2

    echo '============================'
    echo ' Tunnel UP'
    echo '============================'
    ipsec auto --down ${partner_name}_tunnel${tunnel_no}
    if [ $? -ne 0 ]; then
        echo 
        echo ' FAILED'
        echo '============================'
        return 1
    else
        echo
        echo ' OK'
        echo '============================'
        return 0
    fi
}

function restart_ipsec {
    partner_name=$1
    tunnel_no=$2

    echo '============================'
    echo ' Tunnel restart'
    echo '============================'
    echo
    result=0
    down_ipsec $partner_name $tunnel_no ; result=$(( $result + $? ))
    up_ipsec $partner_name $tunnel_no   ; result=$(( $result + $? ))
    
    if [ $result -ne 0 ]; then
        echo 
        echo ' FAILED'
        echo '============================'
        return 1
    else
        echo
        echo ' OK'
        echo '============================'
        return 0
    fi
}

function test_ipsec {
    partner_name=$1
    tunnel_no=$2

    echo '============================'
    echo ' Tunnel test '
    echo " >> $partner_name no.$tunnel_no"
    echo '============================'
    echo 
    echo '============================'
    echo ' Detecting configuration'
    echo '============================'
    clear_variables
    prepare_tunnel_cfg $partner_name

    case $tunnel_no in
        1) ipsec_tunnel_rightvti_address=$ipsec_tunnel1_rightvti_address ;;
        2) ipsec_tunnel_rightvti_address=$ipsec_tunnel2_rightvti_address ;;
        *)
        echo "No tunnel: $tunnel_no"
        return 2
        ;;
    esac

    echo
    echo '============================'
    echo ' Tunnel ICMP test           '
    echo '                            '
    echo '                icmp-->|    '
    echo ' libreswan -> tunnel -> aws '
    echo '============================'
    timeout 15 ping -c2 $ipsec_tunnel_rightvti_address
    if [ $? -ne 0 ]; then
        echo 
        echo 'Test FAILED'
        echo '===================================='
        return 1
    else
        echo
        echo 'Test PASSED'
        echo '===================================='
        return 0
    fi
}