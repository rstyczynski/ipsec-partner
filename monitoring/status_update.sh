#!/bin/bash

umask 222
PATH=$PATH:/opt/ipsec-partner/bin

#
# ipsec
# 

# add trafficstatus
ipsec whack --trafficstatus > /run/ipsec-partner/status/ipsec/whack/trafficstatus.raw
cat /run/ipsec-partner/status/ipsec/whack/trafficstatus.raw | trafficstatus2json.py > /run/ipsec-partner/status/ipsec/whack/trafficstatus

#add
for tunnel in $(cat /run/ipsec-partner/status/ipsec/whack/trafficstatus | jq -r keys[]); do
	cat /run/ipsec-partner/status/ipsec/whack/trafficstatus | jq ".$tunnel" > /run/ipsec-partner/status/ipsec/whack/$tunnel
done

#delete older files
find /run/ipsec-partner/status/ipsec/whack -type f -not -newermt '-1 seconds' -exec rm -f {} \;

#
# ip
#

# add tunnel 
ip -s tunnel > /run/ipsec-partner/status/ip/tunnel/tunnel.raw
cat /run/ipsec-partner/status/ip/tunnel/tunnel.raw | tunnel2json.py > /run/ipsec-partner/status/ip/tunnel/tunnel

#add
for vti in $(cat /run/ipsec-partner/status/ip/tunnel/tunnel | jq -r keys[]); do
	cat /run/ipsec-partner/status/ip/tunnel/tunnel | jq ".$vti" > /run/ipsec-partner/status/ip/tunnel/$vti
done

#delete older files
find /run/ipsec-partner/status/ip/tunnel -type f -not -newermt '-1 seconds' -exec rm -f {} \;

