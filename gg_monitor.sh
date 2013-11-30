#!/bin/bash

#==================================================================#
# GoldenGate monitoring script.                                    #
# Run on Primary database only.                                    #
# Check if GG is running.                                          #
# Check for ABENDED processes and lag using output from GGSCI      #
# command 'info all'.                                              #
# Parameters:                                                      #
# db_name, db_unique_name, max_lag in format hh:mi:ss              #
# Crontab job (one line):                                          #
# 2,32 * * * * /home/oracle/scripts/gg_monitor_new.sh nvcsom1      #
# nvcsom1b 00:30:00 > /home/oracle/scripts/log/gg_monitor.log 2>&1 #
#==================================================================#

# Setup environment for cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2

# Maximum lag in format hh:mi:ss, for example 00:35:00
MAX_LAG=$3

# Generate log file name
LOG_FILE=${WORKING_DIR}/log/gg_monitor_$THE_TIME.log

# Check if PMON is running
if [ `ps -ef | grep ora_pmon_$ORACLE_SID | grep -v grep | wc -l` -eq 0 ]; then
   echo "Oracle is not running."
   # Send e-mail
   exit
fi

echo "Oracle PMON process is running."

#---------------------#
# Check database role #
#---------------------#
CURRENT_ROLE=`cat $DB_ROLE_FILE`
echo Current role: $CURRENT_ROLE

# Is it STANDBY?
if [ "$CURRENT_ROLE" != "PRIMARY" ]
then
    # Yes.
    echo "This is STANDBY database. GG should run on PRIMARY only."

    # Is GG running?
    if [ `ps -ef | grep "./mgr PARAMFILE" | grep -v grep | wc -l` -ne 0 ]
    then
        # Yes
        echo "GoldenGate Manager is running on Standby NVC database" | mailx -s "GoldenGate
 Manager is running on $ORACLE_HOST_NAME for Standby database $ORACLE_SID" $DBA_EMAIL
    else
        echo "GoldenGate is not running."
    fi

    exit
fi

echo "This is PRIMARY database."

if [ `ps -ef | grep "./mgr PARAMFILE" | grep -v grep | wc -l` -eq 0 ]
then
    echo "Golden Gate Manager is not running."

    # Send e-mail
    echo "GoldenGate Manager is not running on Primary NVC database" | mailx -s "GoldenGate Manager is not running on $ORACLE_HOST_NAME for database $ORACLE_SID" $DBA_EMAIL

    exit
fi

echo "Golden Gate is running."

# Output GG information to log file
echo 'INFO ALL' | $GGATE/ggsci > $LOG_FILE

#------------------------#
# Check for ABEND errors #
#------------------------#
if [ `cat $LOG_FILE | grep ABENDED | grep -v grep | wc -l` -eq 0 ]
then
    echo "No ABENDED process."
else
    echo "GoldenGate Process ABENDED on $ORACLE_HOST_NAME for databae $ORACLE_SID"
    cat $LOG_FILE | mailx -s "GoldenGate Process ABENDED on $ORACLE_HOST_NAME for database $ORACLE_SID" $DBA_EMAIL
fi

#
# Check for lags
#
lag=`awk '/RUNNING/ {print $4}' $LOG_FILE | sort -r | grep -v 00:00:00 | head -1`

if [ "$lag" \< "$MAX_LAG" ]
then
    echo "No LAG found."
else
    echo "LAG more than $MAX_LAG was found."
    cat $LOG_FILE | mailx -s "Golden Gate LAG on $ORACLE_HOST_NAME for database $ORACLE_SID more than $MAX_LAG was found" $DBA_EMAIL
fi
