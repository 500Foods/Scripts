#!/bin/bash

uptime_str=$(uptime -p)
weeknum=$(weeknumber.py)
uptime_arr=($uptime_str)

formatted=""

for i in 1 3 5; do
  if [ -n "${uptime_arr[$i]}" ]; then
    formatted+="${uptime_arr[$i]% *}${uptime_arr[$((i+1))]:0:1} "
  fi  
done

echo $weeknum " Up: " $formatted 
