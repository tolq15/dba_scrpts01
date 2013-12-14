#!/bin/bash

#
# Setup environment from cron job
#
. /home/oracle/scripts/.bash_profile_cron $1 $2
export LISTENER=$3

cd $WORKING_DIR

# Check if PMON is running
if [ `ps -ef | grep ora_pmon_$ORACLE_SID | grep -v grep | wc -l` -eq 0 ]; then
   echo "Oracle is not running"
   if [ `ps -ef | grep "tnslsnr $LISTENER -inherit" | grep -v grep | wc -l` -eq 1 ]; then
      echo "LISTENER $LISTENER is running. Stop listener $LISTENER"
      echo "LISTENER $LISTENER is running. Stop listener $LISTENER" | mailx -s "Try to stop listener for $ORACLE_SID on $HOSTNAME" $DBA_EMAIL
      lsnrctl stop $LISTENER
      echo "Listener $LISTENER stopped."
   else
      echo "Listener $LISTENER is not running too."
   fi
   exit
fi

echo "Oracle is running"

# Write current database role to variable
CURRENT_ROLE=`cat $DB_ROLE_FILE`
echo Current role: $CURRENT_ROLE

# Is it STANDBY?
if [ "$CURRENT_ROLE" = "PHYSICAL STANDBY" ];
then
    # Yes. Stop listener if it is running.
    echo "This is STANDBY database."
    if [ `ps -ef | grep "tnslsnr $LISTENER -inherit" | grep -v grep | wc -l` -eq 1 ]; then
        echo "LISTENER $LISTENER is running. Stop listener $LISTENER"
        echo "LISTENER $LISTENER is running. Stop listener $LISTENER" | mailx -s "Try to stop listener for $ORACLE_SID on $HOSTNAME" $DBA_EMAIL
        lsnrctl stop $LISTENER
        echo "Listener $LISTENER stopped."
    else
        echo "Listener $LISTENER is not running."
    fi
    exit
elif [ "$CURRENT_ROLE" = "PRIMARY" ];
then
    echo "This is PRIMARY database. Start listener $LISTENER if it is not running."
    if [ `ps -ef | grep "tnslsnr $LISTENER -inherit" | grep -v grep | wc -l` -eq 0 ]; then
        echo "LISTENER $LISTENER is not running. Start listener $LISTENER"
        echo "LISTENER $LISTENER is not running. Start listener $LISTENER" | mailx -s "Try to start listener for $ORACLE_SID on $HOSTNAME" $DBA_EMAIL
        lsnrctl start $LISTENER
        echo "Listener $LISTENER started."
    else
        echo "Listener $LISTENER is running."
    fi
else
    echo "Can't find the database role to start/stop listener $LISTENER."
    if [ `ps -ef | grep "tnslsnr $LISTENER -inherit" | grep -v grep | wc -l` -eq 0 ]; then
        echo "LISTENER $LISTENER is not running."
    else
        echo "Listener $LISTENER is running."
    fi
    echo "$ORACLE_SID: Can't find the database role." | mailx -s "Can't find the database role to start/stop listener $LISTENER." $DBA_EMAIL
fi

