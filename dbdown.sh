#!/bin/bash

# Setup environment for cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2

# Check if there is pmon process for the database
if [ `ps -ef | grep ${ORACLE_SID} | grep pmon | wc -l` -eq 0 ]
then
    CHECK_OUTPUT0=$(echo "PMON for Database $ORACLE_SID not running")
    CHECK_OUTPUT1=$(echo "=========================================")

    # Add last messages from alert file to e-mail and log file
    CHECK_OUTPUT2=$(tail $ORACLE_BASE/diag/rdbms/$ORACLE_UNQNAME/$ORACLE_SID/trace/alert_$ORACLE_SID.log)

    echo -e "$CHECK_OUTPUT0\n" "$CHECK_OUTPUT1\n" "$CHECK_OUTPUT2"
    echo -e "$CHECK_OUTPUT0\n" "$CHECK_OUTPUT1\n" "$CHECK_OUTPUT2" | mailx -s "PMON process for $ORACLE_SID is down on $HOSTNAME" $DBA_EMAIL
    exit 0
fi

echo "PMON for $ORACLE_SID is running"

#*************************************************************
# Test to see if Oracle is accepting connections
#*************************************************************
CHECK_OUTPUT0=$($ORACLE_HOME/bin/sqlplus -s / as sysdba <<!
set feed off
col instance_name for a15
col status        for a15
col logins        for a15
select instance_name,status,logins,shutdown_pending from v\$instance;
exit
!
)

echo "$CHECK_OUTPUT0"

#*************************#
# If not, e-mail and exit #
#*************************#
if [ `echo "$CHECK_OUTPUT0" | grep -i error | wc -l` -ne 0 ]
then
    CHECK_OUTPUT1=$(echo "======= CANNOT CONNECT TO $ORACLE_SID. LAST ROWS FROM ALERT ============")

    # Add last messages from alert file to e-mail and log file
    CHECK_OUTPUT2=$(tail $ORACLE_BASE/diag/rdbms/$ORACLE_UNQNAME/$ORACLE_SID/trace/alert_$ORACLE_SID.log)

    echo -e "$CHECK_OUTPUT1\n" "$CHECK_OUTPUT2"
    echo -e "$CHECK_OUTPUT0\n" "$CHECK_OUTPUT1\n" "$CHECK_OUTPUT2" | mailx -s "Problem to connect to $ORACLE_SID on $HOSTNAME" $DBA_EMAIL
    exit 0
fi

echo "Oracle SYSDBA login is OK"
