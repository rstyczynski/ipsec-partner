#!/usr/bin/expect

set timeout 150

spawn "./cli_install.sh"

expect "===> In what directory would you like to place the install? (leave blank to use '/root/lib/oracle-cli'):"
send "/var/oracle-cli\r"

set timeout 2
expect "===> Remove this directory? (y/N):" { send "Y\r" }

expect "===> In what directory would you like to place the 'oci' executable? (leave blank to use '/root/bin'):"
send "/bin\r"

expect "===> In what directory would you like to place the OCI scripts? (leave blank to use '/root/bin/oci-cli-scripts'):"
send "/var/oracle-cli/oci-cli-scripts\r"

expect "What optional CLI packages would you like to be installed (comma separated names; press enter if you don't need any optional packages)?:"
send "\r"

expect "===> Modify profile to update your \$PATH and enable shell/tab completion now? (Y/n):"
send "\r"

expect "===> Enter a path to an rc file to update (leave blank to use '/root/.bashrc'):"
send "\r"

