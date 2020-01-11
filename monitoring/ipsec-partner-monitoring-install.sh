#!/bin/bash

what='ipsec-partner monitor install script'
change_label1="added by >>$what<<"
change_label2="by $(whoami) on $(date)"

#
# helper functions
#
function get_ipsec_names {

    DATA=$(cd /etc/ipsec.d/partners; grep '^ipsec_name=' *.cfg 2>/dev/null)
    if [ $? == 0 ]; then
        for line in $(echo $DATA); do
            left=$(echo $line | cut -f1 -d'.')
            right=$(echo $line | cut -f2 -d'=')

            if [ "$left" == "$right" ]; then
                echo $left
            fi
        done
    fi
}

#
# install procedure
#

named_cfg=$1

if [ -z "$named_cfg" ]; then
    echo "Error: provide configuration name."
    exit 1
fi

if [[ "$(get_ipsec_names)" != *"$named_cfg"* ]]; then
    echo "Error: provided cfg not recognized."
    exit 1
fi

echo "Installing packages..."
yum -y install jq httpd


echo -n "Preparing status directories..."
[ -d /run/ipsec-partner ] && rm -rf /run/ipsec-partner

mkdir -p /run/ipsec-partner/status/ipsec/whack
mkdir -p /run/ipsec-partner/status/ip/tunnel

chmod -R 755 /run/ipsec-partner/*
echo OK


echo -n "Making utilities available..."
[ -d /opt/ipsec-partner ] && rm -rf /opt/ipsec-partner
mkdir -p /opt/ipsec-partner/bin
mkdir -p /opt/ipsec-partner/sbin

# user utilities
cp trafficstatus2json.py /opt/ipsec-partner/bin
cp tunnel2json.py /opt/ipsec-partner/bin
cp resource_state_filter.py /opt/ipsec-partner/bin

# system utilities
cp status_update.sh /opt/ipsec-partner/sbin
cp ipsec-partner_oci.sh /opt/ipsec-partner/sbin

chmod +x /opt/ipsec-partner/bin/*.py
chmod +x /opt/ipsec-partner/sbin/*.sh
chmod -R 555 /opt/ipsec-partner/bin/*
chmod -R 500 /opt/ipsec-partner/sbin/*
echo OK

#
echo -n "Updating crontab..."
grep "$change_label1" /etc/crontab >/dev/null
if [ $? -eq 0 ]; then
    echo "Skipped. Change already done."
else
    echo "# >> $change_label1" >>/etc/crontab
    echo '  *  *  *  *  * root      /opt/ipsec-partner/sbin/status_update.sh' >>/etc/crontab
    echo "# << $change_label1" >>/etc/crontab
    echo 'OK'
fi

echo -n "Updating crontab for $named_cfg..."
grep "$change_label1 for $named_cfg" /etc/crontab >/dev/null
if [ $? -eq 0 ]; then
    echo "Skipped. Change already done."
else
    echo "# >> $change_label1 for $named_cfg" >>/etc/crontab
    echo "  *  *  *  *  * root      sleep 5;/opt/ipsec-partner/sbin/ipsec-partner_oci.sh  --ipsec-name $named_cfg --debug NO" >>/etc/crontab
    echo "# << $change_label1 for $named_cfg" >>/etc/crontab
    echo 'OK'
fi


echo -n "Configuring http access..."

cp ipsec-partner.conf  /etc/httpd/conf.d/ipsec-partner.conf 

[ ! -d /var/www/html/ipsec-partner ] && ln -s /run/ipsec-partner/status /var/www/html/ipsec-partner

chcon -R -t httpd_sys_content_t /var/www/html/ipsec-partner
chcon -R -t httpd_sys_content_t /var/www/html/ipsec-partner/ip
chcon -R -t httpd_sys_content_t /var/www/html/ipsec-partner/ip/tunnel
chcon -R -t httpd_sys_content_t /var/www/html/ipsec-partner/ipsec/
chcon -R -t httpd_sys_content_t /var/www/html/ipsec-partner/ipsec/whack/

systemctl restart httpd
echo "OK"

echo -n Running data collection...
/opt/ipsec-partner/sbin/status_update.sh
echo "OK"

echo "Done."

