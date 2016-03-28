#!/bin/bash

# Judge parameter number
if [ $# != 2 ];then
echo 'Need two arguments'
exit 1
fi

# Verify if android device connected normally
if ! adb devices | grep 'device$' > /dev/null; then
    echo 'No available device attached'
fi

package_name=$1

time_str=$(date +%Y%m%d%H%M%S)
cpu_file="cpu${time_str}.txt"
mem_file="mem${time_str}.txt"
gpu_file="gpu${time_str}.txt"

if [ ! -f $cpu_file ]; then
    touch $cpu_file
fi

if [ ! -f $mem_file ]; then
    touch $mem_file
fi

if [ ! -f $gpu_file ]; then
    touch $gpu_file
fi

if [ -e log.txt ]; then
    rm -f log.txt
fi

touch log.txt

adb shell monkey -p $package_name --throttle 500 --ignore-crashes --ignore-timeouts -v -v -v $2 > log.txt &

# Function for getting cpu info
function get_cpu(){
    local cpu_info=$(adb shell dumpsys cpuinfo | grep $1 | awk '{print $1}') 
    local cpu_info_integer=${cpu_info%\%*}
    # time, cpu percentage, cpu integer
    echo "$(date +%Y%m%d%H%M%S) $cpu_info $cpu_info_integer" >> $cpu_file 
}

# dump cpu info
while sleep 1; do
    get_cpu $package_name &
done &

# Function for getting memory info
function get_mem(){
    local mem_info=($(adb shell dumpsys meminfo $1 | grep -E 'Native Heap|Dalvik Heap|TOTAL'))
    # time, total heap alloc, dalvik heap alloc, native heap alloc, dalvik private dirty, native private dirty
    echo "$(date +%Y%m%d%H%M%S) ${mem_info[24]} ${mem_info[16]} ${mem_info[7]} ${mem_info[12]} ${mem_info[3]}" >> $mem_file
}

# dump memory info
while sleep 1; do
    get_mem $package_name &
done &

# Function for getting gpu info
function get_gpu(){
    nums=($(adb shell dumpsys gfxinfo $1 | grep '[[:digit:]]\{1,3\}\.[[:digit:]]\{2\}.*[[:digit:]]\{1,3\}\.[[:digit:]]\{2\}'))

    draw=0
    process=0
    execute=0

    for ((i=0;i<${#nums[*]};i++)); do
        value=${nums[$i]}
        value=${value%.*}
        if [ $value -gt 16 ]; then
            case $((i%3)) in
                0)
                    draw=$((draw+1));;
                1)
                    process=$((process+1));;
                2)
                    execute=$((execute+1));;
            esac
        fi
    done
    # time, frame drop count for draw, frame drop count for process, frame drop count for execute
    echo "$(date +%Y%m%d%H%M%S) $draw $process $execute" >> $gpu_file
}

# dump gpu info
while sleep 1; do
    get_gpu $package_name &
done &

while sleep 5; do
    if ! ps -ax | grep -i monkey | grep -v grep &>/dev/null; then
        ps -ax | grep -i dump.sh | grep -v grep | awk '{print $1}' | xargs kill -9 &>/dev/null
    fi
done &
