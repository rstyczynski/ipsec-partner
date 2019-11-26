#!/bin/bash

unset ipsec-partner-install
function ipsec-partner-install() {

    # in case of error continue
    set +e

    #
    #
    #
    what="libreswan install procedue"
    change_label1="added by >>$what<<"
    change_label2="by $(whoami) on $(date)"

    #
    # prepare paramters
    #

    # determine primary local network adapter
    if [ -z "$if_local" ]; then
        if_local=$(ip link | grep -v link | grep -v LOOPBACK | head -1 | tr -d ' ' | cut -f2 -d':')
        echo "Determined primary local interface: $if_local"
    fi
    if [ -z "$if_local" ]; then
        echo "Error. Cannot determine primary network interface. Specify name as parameter."
        exit 1
    fi

    [ -z "$ipsec_zone" ] && ipsec_zone="ipsec_tunnel"
    [ -z "$install_home" ] && install_home="."

    #
    # helper functions
    #
    function backup_file() {
        file=$1

        cp $file $file.$(date +"%Y%m%d_%H%M%S")
    }

    #
    # install packages
    #
    yum -y install libreswan firewalld nc iftop
    echo "Required software installed."

    #
    # configure kernel
    #
    echo -n "Configuring kernel..."
    grep "$change_label1" /etc/sysctl.conf >/dev/null
    if [ $? -eq 0 ]; then
        echo "Skipped. Change already done."
    else
        cat >>/etc/sysctl.conf <<EOF
#
# START $change_label1 $change_label2
#
net.ipv4.ip_forward = 1
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.$if_local.rp_filter = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
#
# STOP $change_label1 $change_label2
#
EOF
        sysctl -p
        echo "OK"
    fi

    #
    # configure firewalld
    #
    err=0
    firewall-cmd --new-zone=$ipsec_zone --permanent || ((err = err + 1))
    firewall-cmd --zone=$ipsec_zone --add-service="ipsec" --permanent || ((err = err + 1))
    firewall-cmd --zone=$ipsec_zone --set-target=DROP --permanent || ((err = err + 1))
    firewall-cmd --zone=trusted --change-interface=$if_local --permanent || ((err = err + 1))
    firewall-cmd --reload || ((err = err + 1))
    if [ $err -gt 0 ]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "Warning: Firewall configured with errors."
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    else
        echo "Firewall configured."
    fi

    #
    # Configure services
    #
    systemctl start ipsec
    systemctl start firewalld
    echo "Services started."

    systemctl enable ipsec
    systemctl enable firewalld
    echo "Services configured to start at boot."

    #
    # Install ipsec-partner
    #
    echo -n "Add ipsec-partner to /usr/sbin..."
    cp $install_home/ipsec-partner /usr/sbin/ipsec-partner
    chmod +x /usr/sbin/ipsec-partner
    echo "OK"

    echo -n "Register ipsec-partner..."
    source /usr/sbin/ipsec-partner >/dev/null
    echo "OK"

    echo "Configure ipsec-partner..."
    ipsec_configure

    #
    # Done.
    #
    echo "===================================="
    echo "Host configuration completed."
    echo
    echo "Execute ipsec-partner to configure tunnel."

}
