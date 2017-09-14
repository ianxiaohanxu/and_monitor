#!/bin/bash

# Judge parameter number
if [ $# != 2 ];then
    echo 'Need two arguments'
    exit 1
fi

# Verify if android device connected normally
if ! adb devices | grep 'device$' > /dev/null; then
    echo 'No available device attached'
    exit 1
fi

serial_id=$1
package_name=$2
cpu_counter=$(adb shell ls /sys/devices/system/cpu | grep -c "cpu\d\+")
userId=$(adb -s $serial_id shell dumpsys package $package_name | awk '/userId/{print $1}' | awk -F = '{print $2}')
userId=${userId:0:5}
time_str=$(date +%Y%m%d%H%M%S)
mkdir $time_str
cpu_file="$time_str/cpu.csv"
mem_file="$time_str/mem.csv"
gpu_file="$time_str/gpu.csv"
bat_temp="$time_str/bat_temp.csv"
netstats_file="$time_str/netstats.csv"
speed_file="$time_str/speed.csv"

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

# Function for getting cpu info
function get_cpu(){
    cur_time=$(date +"%Y-%m-%d %H:%M:%S")
    cpu_usage=$(adb -s $1 shell top -n 1 | grep -E "${package_name}" | awk '{print $3}' | awk -F % 'BEGIN {count=0;} {count+=$1;} END {print count;}' )
    if [ $cpu_usage -le 100 ]; then
        echo "${cur_time},${cpu_usage}" >> $cpu_file
    fi
}

# dump cpu info
echo "time,cpu total" >> $cpu_file
while sleep 1; do
    get_cpu $serial_id $package_name &
done &

# Function for getting memory info
function get_mem(){
    local mem_info=($(adb -s $1 shell dumpsys meminfo $2 | grep -E 'Native Heap|Dalvik Heap' | awk '{print $7" "$8}'))
    # time, dalvik heap size, dalvik heap alloc, native heap size, native heap alloc
    echo "$(date +"%Y-%m-%d %H:%M:%S"),${mem_info[2]},${mem_info[3]},${mem_info[0]},${mem_info[1]}" >> $mem_file
}

# dump memory info
echo "time,dalvik heap size,dalvik heap alloc,native heap size,native heap alloc" >> $mem_file
while sleep 1; do
    get_mem $serial_id $package_name &
done &

# Function for getting gpu info
function get_gpu(){
    nums=($(adb -s $1 shell dumpsys gfxinfo $2 | sed -n '/Profile data in ms:/,$p' | grep '[[:digit:]]\{1,3\}\.[[:digit:]]\{2\}.*[[:digit:]]\{1,3\}\.[[:digit:]]\{2\}'))

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
    echo "$(date +"%Y-%m-%d %H:%M:%S"),$draw,$process,$execute" >> $gpu_file
}

# dump gpu info
echo "time,draw,process,execute" >> $gpu_file
while sleep 1; do
    get_gpu $serial_id $package_name &
done &

# Function for getting battery temperature
function get_bat_temp(){
    temp=$(adb -s $1 shell dumpsys battery | awk '/temperature/{print $2}')
    temp=${temp:0:3}
    temp=$((temp/10))
    echo "$(date +"%Y-%m-%d %H:%M:%S"),$temp" >> $bat_temp
}

# dump battery temperature info
echo "time,battery_temp" >> $bat_temp
while sleep 1; do
    get_bat_temp $serial_id &
done &

# Getting netstats
function get_rx(){
    rx_list=$(adb -s $1 shell cat /proc/net/xt_qtaguid/stats | awk "/$userId/{print \$6}")
    rx=0
    for item in $rx_list; do
        rx=$((rx+item))
    done
}

function get_tx(){
    tx_list=$(adb -s $1 shell cat /proc/net/xt_qtaguid/stats | awk "/$userId/{print \$8}")
    tx=0
    for item in $tx_list; do
        tx=$((tx+item))
    done
}

get_rx $serial_id
start_rx=$rx
start_rspeed=$rx
get_tx $serial_id
start_tx=$tx
start_tspeed=$tx

function get_speed(){
    rspeed=$((rx-start_rspeed))
    tspeed=$((tx-start_tspeed))
    speed=$((rspeed+tspeed))
    cur_time=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$cur_time,$rspeed,$tspeed,$speed" >> $speed_file
}

# dump speed info
echo "time,r_speed,t_speed,total_speed" >> $speed_file
while sleep 1; do
    get_rx $serial_id
    get_tx $serial_id
    get_speed &
    start_rspeed=$rx
    start_tspeed=$tx
done &

read -p "Action on your phone, press Enter key after you finish..."
#rx_list=$(adb -s $1 shell cat /proc/net/xt_qtaguid/stats | grep $userId | awk '{print $6}')
#rx=0
#for item in $rx_list; do
#    rx=$((rx+item))
#done
#
#tx_list=$(adb -s $1 shell cat /proc/net/xt_qtaguid/stats | grep $userId | awk '{print $8}')
#tx=0
#for item in $tx_list; do
#    tx=$((tx+item))
#done
get_rx $serial_id
get_tx $serial_id

end_rx=$rx
end_tx=$tx
rbyte=$((end_rx-start_rx))
tbyte=$((end_tx-start_tx))
total_byte=$((rbyte+tbyte))
echo "rbyte,tbyte,total_byte" > $netstats_file
echo "$rbyte,$tbyte,$total_byte" >> $netstats_file

ps -ax | grep dump.sh | grep -v grep | awk '{print $1}' | xargs kill -9
