#!/bin/bash

#==========================================================
# ctl_gg_clear_log.sh
#
# Update: 2012/5/30
# Daily script to clear Golden Gate event log
# Update: 07/16/2012
# Replace temp file with CURRENT_ROLE to store query result
#==========================================================

# Setup environment for cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2

# Write current database role to variable
CURRENT_ROLE=$(sqlplus -s / as sysdba <<EOF
set feed off
set head off
set pages 0
select DATABASE_ROLE from v\$database;
exit
EOF
)

# Is it STANDBY?
if [ "$CURRENT_ROLE" = "PRIMARY" ];
then
    echo "This is PRIMARY database. Keep 2 days of logs."
    cd $GGATE

    #we keep 2 days
    cp -p ggserr.log.bkup ggserr.log.bkup2
    cp -p ggserr.log      ggserr.log.bkup
    cat /dev/null > ggserr.log
else
    echo "This is not PRIMARY database. Do nothing."
fi
