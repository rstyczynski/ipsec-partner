#!/bin/bash

what='ipsec-partner monitor install script'
change_label1="added by >>$what<<"
change_label2="by $(whoami) on $(date)"

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

cp trafficstatus2json.py /opt/ipsec-partner/bin
cp tunnel2json.py /opt/ipsec-partner/bin
cp status_update.sh /opt/ipsec-partner/sbin

chmod +x /opt/ipsec-partner/bin/*.py
chmod +x /opt/ipsec-partner/sbin/*.sh
chmod -R 555 /opt/ipsec-partner/bin/*
chmod -R 500 /opt/ipsec-partner/sbin/*
echo OK

#
echo -n "Updating crontab..."
cat /etc/crontab | grep "$change_label1" 
if [ $? -eq 0 ]; then
    echo "Skipped. Change already done."
else
    echo "# >> $change_label1" >>/etc/crontab
    echo '  *  *  *  *  * root      /opt/ipsec-partner/sbin/status_update.sh' >>/etc/crontab
    echo "# << $change_label1" >>/etc/crontab
    echo 'OK'
fi


echo -n "Configuring http access..."

cp ipsec-partner.conf  /etc/httpd/conf.d/ipsec-partner.conf 

ln -s /run/ipsec-partner/status /var/www/html/ipsec-partner

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

