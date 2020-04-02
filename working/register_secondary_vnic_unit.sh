#!/bin/bash

#
# download vnic script
#
mkdir /opt/secondary_vnic
cd /opt/secondary_vnic
wget https://docs.cloud.oracle.com/iaas/Content/Resources/Assets/secondary_vnic_all_configure.sh
chmod u+x secondary_vnic_all_configure.sh

#
# creat unit definition
#
cat > /etc/systemd/system/secondary_vnic_all_configure.service <<EOF
[Unit]
Description=Add the secondary VNIC at boot
After=basic.target

[Service]
Type=oneshot
ExecStart=/opt/secondary_vnic/secondary_vnic_all_configure.sh -c

[Install]
WantedBy=default.target
EOF

#
# enable
#
chmod 664 /etc/systemd/system/secondary_vnic_all_configure.service
systemctl enable /etc/systemd/system/secondary_vnic_all_configure.service
systemctl list-unit-files|egrep secondary_vnic_all_configure.service

#
# start interfaces
#
systemctl start /etc/systemd/system/secondary_vnic_all_configure.service

echo "Done."

