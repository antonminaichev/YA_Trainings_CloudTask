import time
from subprocess import check_output, getoutput
import os
import json

pid_numb = os.getpid()
my_variable = None
with open('/proc/' + str(pid_numb) + '/status', 'r') as f:
    my_variable = f.read()
cmd = 'ls -l /proc/' + str(pid_numb) + '/fd | wc -l'
output = getoutput(cmd)
f_descriptors = str(int(output) - 1) #-1 because 0 line is explaination
print(f_descriptors)
number = my_variable.find('VmRSS')
mem_proc = getoutput('cat /proc/' + str(pid_numb) + '/status | grep VmRSS  | awk -F \' \' \'{print $2,$3}\'')
print(mem_proc)
exe_path = getoutput('readlink /proc/' + str(pid_numb) + '/exe')
print(exe_path)
cpus_number = getoutput('lscpu | grep CPU | sed ''2!d'' | tr -d " \t\n\r" | tail -c 1')
print(cpus_number)
cpu_name = getoutput('lscpu | grep Model\' \'name | cut -d: -f2').strip()
print(cpu_name)
mem_size = getoutput('lsmem | grep Total\' \'online | cut -d: -f2').lstrip()
print(mem_size)
disk_size = getoutput('lsblk /dev/sda | sed \'2!d\' | awk -F \' \' \'{print $4}\'')
print(disk_size)

dictionary = {
    "descriptors": f_descriptors,
    "mem_proc": mem_proc,
    "exe_path": exe_path,
    "cpus_number": cpus_number,
    "cpu_name": cpu_name,
    "mem_size": mem_size,
    "disk_size": disk_size
}

json_object = json.dumps(dictionary, indent=len(dictionary)) 

with open("json/info_host.json", "w") as outfile:
    outfile.write(json_object)

