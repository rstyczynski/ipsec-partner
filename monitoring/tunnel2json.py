#!/bin/python2

import fileinput
import re
import sys
import json
import time
import datetime
import argparse


parser = argparse.ArgumentParser("trafficstatus2json.py")
parser.add_argument("-o", dest="json_out", help="filename to write data in json format")
args = parser.parse_args()

json_out=args.json_out


vti_format="(\w+): ip/ip remote ([\w\.]+) local ([\w\.]+) (.+) key (\d+)"
vti_rx_format="\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)"
vti_tx_format="\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)"

vti_attributes = dict()
vti_cnt = -2
for line in sys.stdin:
    if json_out is not None:
        print line,   
    
    vti_cnt=vti_cnt+1

    vti_desc = re.match(vti_format, line)
    if vti_desc:
        vti_cnt = 0
        vti_name=''

    if vti_cnt == 0:
        vti_name=vti_desc.group(1)

        vti_ifheader={
                'name': vti_desc.group(1),
                'remote_id': vti_desc.group(2),
                'local_id': vti_desc.group(3),
                'attributes': vti_desc.group(4),
                'key': vti_desc.group(5),
		'capture_time': int(time.time()),
		'capture_time_iso': datetime.datetime.utcfromtimestamp(int(time.time())).isoformat()
            }

        vti_attributes.update({vti_name: vti_ifheader})
        
    elif vti_cnt == 1:
        expected = 'RX: Packets    Bytes        Errors CsumErrs OutOfSeq Mcasts\n'
        if(line != expected):
            print('Expected:', expected)
            print('Actual', line)
            raise ValueError('Expected RX line not found')
    elif vti_cnt == 2:
        vti_rxdesc = re.match(vti_rx_format, line)
        if vti_rxdesc:
            vti_ifheader={
                'Packets': int(vti_rxdesc.group(1)),
                'Bytes': int(vti_rxdesc.group(2)),
                'Errors': int(vti_rxdesc.group(3)),
                'CsumErrs': int(vti_rxdesc.group(4)),
                'OutOfSeq': int(vti_rxdesc.group(5)),
                'Mcasts': int(vti_rxdesc.group(6))
            }
            vti_attributes[vti_name].update({'RX': vti_ifheader})
    elif vti_cnt == 3:
        expected='TX: Packets    Bytes        Errors DeadLoop NoRoute  NoBufs\n'
        if(line != expected):
            print('Expected:', expected)
            print('Actual', line)
            raise ValueError('Expected TX line not found')
    elif vti_cnt == 4:
        vti_txdesc = re.match(vti_tx_format, line)
        if vti_txdesc:
            vti_ifheader={
                'Packets': int(vti_txdesc.group(1)),
                'Bytes': int(vti_txdesc.group(2)),
                'Errors': int(vti_txdesc.group(3)),
                'DeadLoop': int(vti_txdesc.group(4)),
                'NoRoute': int(vti_txdesc.group(5)),
                'NoBufs': int(vti_txdesc.group(6))
            }
            vti_attributes[vti_name].update({'TX': vti_ifheader})
    else:
        raise ValueError('Unknown format.')

if json_out is not None:
    with open(json_out, 'w') as outfile:
        json.dump(vti_attributes, outfile)
else:
    print json.dumps(vti_attributes),



