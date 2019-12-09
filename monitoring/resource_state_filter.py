#!/bin/python

from __future__ import print_function

import os
import sys
import readline
import argparse

import time

import pickle
import json

# current state
#
contexts = {}

def get_context(resource_name):
    global contexts

    if not resource_name in contexts:
        context = {}
        context['age_down'] = -1
        context['age_up'] = -1
        context['age_up2down'] = 0
        context['age_down2up'] = 0
        context['failed_exit_counter'] = 0
        context['event_time'] = -1
        context['state'] = 'UNDEFINED'
        context['flapping'] = False
        contexts[resource_name] = context

    context=contexts[resource_name]
    #
    return context

#
# helper
#
def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

#
# logic
#
def report_state(resource_name, header = False):
    #
    global out_format
    #

    if not header:
        context = get_context(resource_name)
        #
        age_down=context['age_down']
        age_up=context['age_up']
        failed_exit_counter=context['failed_exit_counter']
        #
        #
        event_time=context['event_time']
        measurement=context['measurement']
        OK_entry_barrier=context['OK_entry_barrier']
        OK_exit_barrier=context['OK_exit_barrier']
        failed_entry_barrier=context['failed_entry_barrier']
        failed_exit_barrier=context['failed_exit_barrier']

        failed = context['failed']
        OK = context['OK']
        state = context['state']
        state_numeric = context['state_numeric']
        alarm_raise = context['alarm_raise']
        alarm_dismiss = context['alarm_dismiss']

        age_up2down = context['age_up2down']
        age_down2up = context['age_down2up']
        flapping = context['flapping']
        flapping_raise = context['flapping_raise']
        flapping_dismiss = context['flapping_dismiss']
    #
    #
    if out_format == 'json':
        print(json.dumps(context, indent=4, sort_keys=True))
    else:
        if resource_name == 'simulation':
            if header:
                print('event_time', 'measurement', 
                'age_down', 'age_up', 'failed_exit_counter', 
                'failed', 'OK', 
                'OK_entry_barrier', 'OK_exit_barrier', 'failed_entry_barrier', 'failed_exit_barrier', sep=' ')
            else:
                print(event_time, measurement, age_down, age_up, failed_exit_counter, failed, OK, 
                OK_entry_barrier, OK_exit_barrier, failed_entry_barrier, failed_exit_barrier, sep=' ')
        else:
            if header:
                print('event_time', 'measurement',
                'state', 'state_numeric',
                'alarm_raise', 'alarm_dismiss',
                'flapping_raise', 'flapping_dismiss', 'flapping', 
                'OK_entry_barrier', 'OK_exit_barrier', 'failed_entry_barrier', 'failed_exit_barrier',
                'failed', 'OK', 
                'age_down', 'age_down2up', 'age_up', 'age_up2down', 'failed_exit_counter', sep=' ')
            else:
                print(event_time, measurement,
                state.ljust(13), str(state_numeric).rjust(3),
                str(alarm_raise).ljust(5), str(alarm_dismiss).ljust(5),
                str(flapping_raise).ljust(5), str(flapping_dismiss).ljust(5), str(flapping).ljust(5), 
                str(OK_entry_barrier).ljust(5), str(OK_exit_barrier).ljust(5), 
                str(failed_entry_barrier).ljust(5), str(failed_exit_barrier).ljust(5),
                str(failed).ljust(5), str(OK).ljust(5), 
                age_down, age_down2up, age_up, age_up2down, failed_exit_counter, sep=' ')


def process_event(event_time, resource_name, measurement):
    #
    global time_before_down, time_before_up
    # 
    context = get_context(resource_name)
    #
    age_down=context['age_down']
    if age_down == -1:
        age_down = 0
    #
    age_up=context['age_up']
    if age_up == -1:
        age_up = 0
    #
    previous_event_time=context['event_time']
    if previous_event_time == -1:
        previous_event_time = int(time.time())-1
    #
    previous_failed_exit_counter = context['failed_exit_counter']
    previous_state = context['state']

    if 'flapping' in context:
        flapping = context['flapping']
    else:
        flapping = False

    previous_flapping = flapping

        
    #
    #
    time_lap = event_time-previous_event_time
    #
    #
    if measurement == 0:
        age_up = 0
        age_down = age_down + time_lap
    elif measurement == 1:
        age_down = 0
        age_up = age_up + time_lap
    else:
        eprint('Error: measurement may be integer 0 or 1.')
        exit(1)
    #
    #
    OK_entry_barrier = age_up > time_before_up
    #
    #
    if age_down > time_before_down:
        failed_exit_counter = previous_failed_exit_counter + 1
    else:
        if OK_entry_barrier:
            failed_exit_counter = 0
        else:
            failed_exit_counter = previous_failed_exit_counter
    #
    #
    failed = failed_exit_counter > 0
    
    OK_exit_barrier= not(failed) and not(OK_entry_barrier) 
    OK = OK_entry_barrier or OK_exit_barrier

    failed_entry_barrier = failed and (failed_exit_counter != previous_failed_exit_counter)
    failed_exit_barrier = failed and (failed_exit_counter == previous_failed_exit_counter) 
    #
    # compute curent state
    alarm_raise = False
    alarm_dismiss = False

    flapping_raise = False
    flapping_dismiss = False

    age_up2down = 0
    age_down2up = 0

    if OK_exit_barrier:
        state = 'UNSTABLE'
        state_numeric = 50
        if previous_state == state:
            age_up2down = context['age_up2down'] + time_lap

    if failed_entry_barrier:
        state = 'FAILED'
        state_numeric = 10
        #
        if previous_state <> state:
            alarm_raise = True
            alarm_dismiss = False
            if flapping:
                flapping_dismiss = True
        else:
            alarm_raise = False
        flapping = False

    if failed_exit_barrier:
        state = 'STABILISING'
        state_numeric = 50
        if previous_state == state:
            age_down2up = context['age_down2up'] + time_lap
    
    if OK_entry_barrier:
        state = 'OK'
        state_numeric = 100
        if previous_state <> state:
            alarm_dismiss = True
            alarm_raise = False
            if flapping:
                flapping_dismiss = True
        else:
            alarm_dismiss = False
        flapping = False

    if age_up2down > time_before_down or age_down2up > time_before_up:
        flapping = True
        if flapping <> previous_flapping:
            flapping_raise = True

    if flapping:
        state = 'FLAPPING'
        state_numeric = 25
    #
    #
    #
    #
    context['resource_name']=resource_name
    #
    context['state']=state
    context['state_numeric']=state_numeric
    #
    context['alarm_raise']=alarm_raise
    context['alarm_dismiss']=alarm_dismiss
    #
    context['flapping'] = flapping
    context['flapping_raise'] = flapping_raise
    context['flapping_dismiss'] = flapping_dismiss
    #
    context['failed_exit_counter']=failed_exit_counter
    context['event_time']=event_time
    #
    context['measurement']=measurement
    context['age_down']=age_down
    context['age_up']=age_up
    context['age_up2down'] = age_up2down
    context['age_down2up'] = age_down2up
    #
    context['failed']=failed
    context['OK']=OK
    context['OK_entry_barrier']=OK_entry_barrier
    context['OK_exit_barrier']=OK_exit_barrier
    context['failed_entry_barrier']=failed_entry_barrier
    context['failed_exit_barrier']=failed_exit_barrier


def simulateExcel():
    #
    # echo "1 1 1 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 0 1 1 0 1 0 1 0 1 1 1 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1  "| tr ' ' '\n' | python resource_state_observer_v2.py | sha1sum | grep d0c0d48407e806e505b6af332685c4dc9481a4a4 && echo OK || echo Error.
    #

    context = get_context('simulation')
    #
    context['event_time'] = 0
    #
    event_time = 1
    #
    for cnt in range(0, 13):
        measurement=1
        process_event(event_time, 'simulation', measurement)
        event_time = event_time + 1
        report_state('simulation')
    #
    for cnt in range(0, 13):
        measurement=0
        process_event(event_time, 'simulation', measurement)
        event_time = event_time + 1
        report_state('simulation')
    #
    measurement=1
    process_event(event_time, 'simulation', measurement)
    event_time = event_time + 1
    report_state('simulation')
    #   
    for cnt in range(0, 13):
        measurement=0
        process_event(event_time, 'simulation', measurement)
        event_time = event_time + 1
        report_state('simulation')
    #
    for cnt in range(0, 5):
        measurement=1
        process_event(event_time, 'simulation', measurement)
        event_time = event_time + 1
        report_state('simulation')       

    #
    measurement=0
    process_event(event_time, 'simulation', measurement)
    event_time = event_time + 1
    report_state('simulation')
    measurement=1
    process_event(event_time, 'simulation', measurement)
    event_time = event_time + 1
    report_state('simulation')
    #
    for cnt in range(0, 3):
        measurement=1
        process_event(event_time, 'simulation', measurement)
        event_time = event_time + 1
        report_state('simulation')
        measurement=0
        process_event(event_time, 'simulation', measurement)
        event_time = event_time + 1
        report_state('simulation')
    #
    for cnt in range(0, 3):
        measurement=1
        process_event(event_time, 'simulation', measurement)
        event_time = event_time + 1
        report_state('simulation')
    #
    for cnt in range(0, 10):
        measurement=0
        process_event(event_time, 'simulation', measurement)
        event_time = event_time + 1
        report_state('simulation')
    #
    for cnt in range(0, 10):
        measurement=1
        process_event(event_time, 'simulation', measurement)
        event_time = event_time + 1
        report_state('simulation')


#
# parse arguments
#
desc = 'resource_state_filter.py'

parser = argparse.ArgumentParser(desc)
parser.add_argument("-r", "--resource", help="resource name", required=True)
parser.add_argument("-c", "--conditions", help="resource state literals for up/down")
parser.add_argument("-d", "--time_before_down", help="lasting of negative measurement to switch status to FAILED")
parser.add_argument("-u", "--time_before_up", help="lasting of possitive measurement to switch status to OK")
parser.add_argument("-f", "--format", help="output format. csv or json")
parser.add_argument("-p", "--persistance", help="directory to keep resource state")
parser.add_argument("-e", "--erase", help="erase resource state from disk", action="store_true")
parser.add_argument("-s", "--simulate", help="generate simulation", action="store_true")

args = parser.parse_args()


if args.resource:
    resource_name=args.resource

if args.persistance:
    state_dir = args.persistance
else:
    state_dir = '/run/user/'+ str(os.getuid())

if args.erase:
    state_file = os.path.join(state_dir, resource_name + '.dictionary')
    try:
        os.remove(state_file)
    except:
        pass
    exit()

if args.time_before_down:
    time_before_down=int(args.time_before_down)
else:
    time_before_down = 5

if args.time_before_up:
    time_before_up=int(args.time_before_up)
else:
    time_before_up = 5

if args.format == 'csv':
    out_format = 'csv' 
else:
    out_format = 'json'

if args.simulate:
    simulateExcel()
    exit()

#
# main
#

# read state
state_file = os.path.join(state_dir, resource_name + '.dictionary')
try:
    with open(state_file, 'rb') as config_dictionary_file:
        context = pickle.load(config_dictionary_file)
        contexts[resource_name] = context
except:
    pass

# keep current config
context = get_context(resource_name)
context['user_config'] = vars(args)

# 
measurements = dict()
if args.conditions:
    try:
        for up_label in args.conditions.split('/')[0].split(','):
            measurements[up_label] = 1

        for down_label in args.conditions.split('/')[1].split(','):
            measurements[down_label] = 0
    except:
       eprint("Error. Provide conditions in format up1,up2/down1,down2,down3.")
       exit(1)
else:
    measurements['up'] = 1
    measurements['ok'] = 1
    measurements['1'] = 1

    measurements['down'] = 0
    measurements['failed'] = 0
    measurements['0'] = 0
    
    context['measurement'] = measurements

#
if out_format == 'csv' and 'header_printed' not in context:
    report_state(resource_name, True)
    context['header_printed'] = True

keep_reading=True
while keep_reading:
    #
    try:
        user_input = raw_input().lower()
        event_time = int(time.time())
        #
        if user_input in measurements:
            measurement = measurements[user_input]
            process_event(event_time, resource_name, measurement)
            
            contexts[resource_name]['user_input'] = user_input

            report_state(resource_name)
        else:
            if user_input == 'exit' or user_input == '':
                keep_reading=False
            else:
                eprint("Warning. Type 'exit', or empty line to exit, or one of acceptable states: " + str(measurements.keys()) + ', but received: ' + user_input)
    except:
        keep_reading=False

# save state
with open(state_file, 'wb') as config_dictionary_file:
    context = contexts[resource_name]
    pickle.dump(context, config_dictionary_file)
#
exit()
