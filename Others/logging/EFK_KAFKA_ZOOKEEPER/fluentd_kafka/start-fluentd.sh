#!/bin/bash
/usr/sbin/td-agent 2>&1 >> /var/log/fluentd.log &

while true 
do 
	sleep 10
done
