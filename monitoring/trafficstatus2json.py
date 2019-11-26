#!/bin/python2

import sys
import fileinput
import re
import json
import time
import datetime
import argparse


parser = argparse.ArgumentParser("trafficstatus2json.py")
parser.add_argument("-o", dest="json_out", help="filename to write data in json format")
args = parser.parse_args()

json_out=args.json_out

pluto_trafficstatus_format="\d+\s#(\d+):\s\"(\w+)\",\stype=(\w+),\sadd_time=(\d+),\sinBytes=(\d+),\soutBytes=(\d+),\sid='(.+)'"
for line in sys.stdin:
    if json_out is not None:
        print(line)

    #line="006 #99: \"ManthanSFTP_tunnel2\", type=ESP, add_time=1574579214, inBytes=0, outBytes=0, id='52.58.29.21'"

    m = re.match(pluto_trafficstatus_format, line)
    if m:
        trafficstatus = {
            m.group(2): {
		'pluto_id': m.group(1),
                'name': m.group(2),
                'type': m.group(3),
                'add_time': int(m.group(4)),
		'add_time_iso': datetime.datetime.utcfromtimestamp(int(m.group(4))).isoformat(),
                'inBytes':  int(m.group(5)),
                'outBytes': int(m.group(6)),
                'id': m.group(7),
		'capture_time': int(time.time()),
		'capture_time_iso': datetime.datetime.utcfromtimestamp(int(time.time())).isoformat()
            }
        }
    	#print(json.dumps(trafficstatus))
        if json_out is not None:
            with open(json_out, 'w') as outfile:
                json.dump(trafficstatus, outfile)
        else:
            print(json.dumps(trafficstatus))

