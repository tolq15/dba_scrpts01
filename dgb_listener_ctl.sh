#!/bin/bash

#
# Script to start Data Guard Broker listener if it is not running.
#

#
# Setup environment from cron job
#
. /home/oracle/scripts/.bash_profile_cron $1 $2
export LISTENER=$3

if [ `ps -ef | grep "tnslsnr $LISTENER -inherit" | grep -v grep | wc -l` -eq 0 ]; then
    echo "LISTENER $LISTENER is not running. Start listener $LISTENER"
    lsnrctl start $LISTENER
    echo "Listener $LISTENER started."
else
    echo "Listener $LISTENER was running."
fi

