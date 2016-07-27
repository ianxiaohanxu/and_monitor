#!/bin/bash

# Judge parameter number
if [ $# != 1 ];then
    echo 'Need only one argument'
    exit 1
fi

# Verify if android device connected normally
if ! adb devices | grep 'device$' > /dev/null; then
    echo 'No available device attached'
    exit 1
fi

package_name=$1
userId=$(adb shell dumpsys package com.yx | awk '/userId/{print $1}' | awk -F = '{print $2}')

time_str=$(date +%Y%m%d%H%M%S)
mkdir $time_str
cpu_file="$time_str/cpu.csv"
mem_file="$time_str/mem.csv"
gpu_file="$time_str/gpu.csv"
bat_temp="$time_str/bat_temp.csv"
netstats_file="$time_str/netstats.csv"

if [ ! -f $cpu_file ]; then
    touch $cpu_file
fi

if [ ! -f $mem_file ]; then
    touch $mem_file
fi

if [ ! -f $gpu_file ]; then
    touch $gpu_file
fi

if [ ! -f $bat_temp ]; then
    touch $bat_temp
fi

if [ ! -f $netstats_file ]; then
    touch $netstats_file
fi

#if [ -e log.txt ]; then
#    rm -f log.txt
#fi
#
#touch log.txt
#
#adb shell monkey -p $package_name --throttle 500 --ignore-crashes --ignore-timeouts -v -v -v $2 > log.txt &

# Function for getting cpu info
function get_cpu(){
    local cpu_info=$(adb shell dumpsys cpuinfo | grep "$1: " | awk '{print $1","$3","$6}') 
    # local cpu_info_integer=${cpu_info%\%*}
    # time, cpu percentage
    echo "$(date +%Y%m%d%H%M%S),$cpu_info" >> $cpu_file 
}

# dump cpu info
echo "time,cpu total,cpu user,cpu kernel" >> $cpu_file
while sleep 1; do
    get_cpu $package_name &
done &

# Function for getting memory info
function get_mem(){
    local mem_info=($(adb shell dumpsys meminfo $1 | grep -E 'Native Heap|Dalvik Heap' | awk '{print $7" "$8}'))
    # time, dalvik heap size, dalvik heap alloc, native heap size, native heap alloc
    echo "$(date +%Y%m%d%H%M%S),${mem_info[2]},${mem_info[3]},${mem_info[0]},${mem_info[1]}" >> $mem_file
}

# dump memory info
echo "time,dalvik heap size,dalvik heap alloc,native heap size,native heap alloc" >> $mem_file
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
    echo "$(date +%Y%m%d%H%M%S),$draw,$process,$execute" >> $gpu_file
}

# dump gpu info
echo "time,draw,process,execute" >> $gpu_file
while sleep 1; do
    get_gpu $package_name &
done &

# Function for getting battery temperature
function get_bat_temp(){
    temp=$(adb shell dumpsys battery | awk '/temperature/{print $2}')
    temp=${temp:0:3}
    temp=$((temp/10))
    echo "$(date +%Y%m%d%H%M%S),$temp" >> $bat_temp
}

# dump battery temperature info
echo "time,battery_temp" >> $bat_temp
while sleep 1; do
    get_bat_temp &
done &

# Getting netstats
rx_list=$(adb shell cat /proc/net/xt_qtaguid/stats | awk "/$userId/{print \$6}")
rx=0
for item in $rx_list; do
    rx=$((rx+item))
done

tx_list=$(adb shell cat /proc/net/xt_qtaguid/stats | awk "/$userId/{print \$8}")
tx=0
for item in $tx_list; do
    tx=$((tx+item))
done

start_rx=$rx
start_tx=$tx

read -p "Please press Enter to continue..."
rx_list=$(adb shell cat /proc/net/xt_qtaguid/stats | awk "/$userId/{print \$6}")
rx=0
for item in $rx_list; do
    rx=$((rx+item))
done

tx_list=$(adb shell cat /proc/net/xt_qtaguid/stats | awk "/$userId/{print \$8}")
tx=0
for item in $tx_list; do
    tx=$((tx+item))
done

end_rx=$rx
end_tx=$tx
rbyte=$((end_rx-start_rx))
tbyte=$((end_tx-start_tx))
total_byte=$((rbyte+tbyte))
echo "rbyte,tbyte,total_byte" > $netstats_file
echo "$rbyte,$tbyte,$total_byte" >> $netstats_file

ps -ax | grep ./dump.sh | grep -v grep | awk '{print $1}' | xargs kill -9
#while sleep 5; do
#    if ! ps -ax | grep -i monkey | grep -v grep &>/dev/null; then
#        ps -ax | grep -i dump.sh | grep -v grep | awk '{print $1}' | xargs kill -9 &>/dev/null
#    fi
#done &
