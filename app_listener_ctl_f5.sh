#!/bin/bash

#
# Script to start listener if it is not running.
# F5 is configured to redirect application to current Primary database.
#

#
# Setup environment from cron job
#
. /home/oracle/scripts/.bash_profile_cron $1 $2
export LISTENER=$3

if [ `ps -ef | grep "tnslsnr $LISTENER -inherit" | grep -v grep | wc -l` -eq 0 ]; then
    echo "LISTENER $LISTENER is not running. Start listener $LISTENER"
    echo "LISTENER $LISTENER is not running. Start listener $LISTENER" | mailx -s "Try to start listener for $ORACLE_SID on $HOSTNAME" $DBA_EMAIL
    lsnrctl start $LISTENER
    echo "Listener $LISTENER started."
else
    echo "Listener $LISTENER was running."
fi
