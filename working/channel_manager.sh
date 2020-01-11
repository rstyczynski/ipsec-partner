tunnel_status_registry=~/watch.me


function set_tmp {
    ipsec_name=$1

    tmp_root=/tmp/$ipsec_name; mkdir -p $tmp_root
    tmp=/tmp/$ipsec_name/$$; mkdir -p $tmp
}

function get_tunnel_state {
    ipsec_name=$1
    tunnel_name=$2

    set_tmp $ipsec_name

    cd $tunnel_status_registry/$ipsec_name 
    ls -t ${tunnel_name}.* | head -1 | cut -f2 -d'.' | tr '[a-z]' '[A-Z]' >$tmp/status
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "UNKNOWN"
        cd - >/dev/null
        return 1
    fi
    cd - >/dev/null

    tunnel_status=$(< $tmp/status)
    case $tunnel_status in
        AVAILABLE | DOWN | UP | FAILED | OPERATIONAL)
            echo "$tunnel_status"
            return 0
        ;;
        *)
            echo "UNKNOWN"
            return 1
        ;;
    esac
}


function channel_manager {
    ipsec_name=$1
    state_file=$2

    set_tmp $ipsec_name

    # protect script from parallel executions
    # src: https://linuxaria.com/howto/linux-shell-introduction-to-flock
    #
    exec 9>$tmp_root/get_tunnel_state.lock
    flock --timeout 5 -n 9 
    if [ $? -ne 0 ]; then
        echo "Error. Only one manager per ipsec channel may be started at the same time. Exiting..."
        return 1
    fi

    #
    # src: https://www.linuxjournal.com/content/linux-filesystem-events-inotify
    #
    # inotifywait -e close_write -m $tunnel_status_registry/$ipsec_name | while read LINE; do 
    #     if [[ $LINE == *"CLOSE_WRITE,CLOSE"* ]]; then
    #         IFS=' ' read -ra EVENT <<< "$LINE"
    #         echo "DEBUG: $LINE"

            # IFS='.' read -ra TUNNEL_STATE <<< "${EVENT[2]}" 

            IFS='.' read -ra TUNNEL_STATE <<< "$state_file" 
            tunnel_name=${TUNNEL_STATE[0]} 
            tunnel_state=${TUNNEL_STATE[1]}

            if [ "$tunnel_name" == 'channel' ] ; then
                echo "DEBUG. Channel state."
            elif [ "$(echo $tunnel_name | sed 's/[0-9]//g')" != 'tunnel' ]; then
                echo "Warning. Illegal file detected."
            else
                tunnel_state_verification=$(get_tunnel_state $ipsec_name $tunnel_name)
                if [ "$tunnel_state" != "$tunnel_state_verification" ]; then
                    echo "Error. Reported uncostitent state. Cause: $tunnel_state vs. $tunnel_state_verification"
                else
                    echo "DEBUG: $tunnel_name $tunnel_state"

                    PROCESS=YES
                    case $tunnel_name in
                        tunnel1)
                            tunnel1_state=$tunnel_state
                            tunnel2_state=$(get_tunnel_state $ipsec_name tunnel2)
                        ;;
                        tunnel2)
                            tunnel2_state=$tunnel_state
                            tunnel1_state=$(get_tunnel_state $ipsec_name tunnel1)
                        ;;
                        *)
                            echo "Warning. Illegal tunnel file detected."
                            PROCESS=NO
                        ;;
                    esac

                    if [ "$PROCESS" == "YES" ]; then
                        channel_state=$tunnel1_state:$tunnel2_state
                        touch $tunnel_status_registry/channel.$channel_state
                        echo "DEBUG. Channel $ipsec_name is in state: $channel_state"

                        case $channel_state in
                            DOWN:FAILED | UP:FAILED | AVAILABLE:FAILED)
                                # must be done in this process to have excelusive access to both channels
                                echo "Failover to 1"
                            ;;
                            FAILED:DOWN | FAILED:UP | FAILED:AVAILABLE)
                                # must be done in this process to have excelusive access to both channels
                                echo "Failover to 2"
                            ;;     
                            FAILED:FAILED)
                                # must be done in this process to have excelusive access to both channels
                                echo "Recover"
                            ;;                   
                            *)
                            ;;
                        esac
                    fi #process
                fi # state consistent
            fi #channel
    #     fi #correct file system EVENT
    # done
}

channel_manager $@

