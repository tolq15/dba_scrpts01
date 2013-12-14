#!/bin/bash

#--------------------------------
# Table was created as
#create table dba_monitor.day_redo_volume_gb
#(the_day        date,
# logswitch      number,
# redo_volume_gb number
#);
# This script will run each week:
# 56 1 * * 5 /home/oracle/scripts/populate_redo_volume_monitor.sh nvcsom1 nvcsom1b > /home/oracle/scripts/log/populate_redo_volume_monitor_nvcsom1.log 2>&1
#--------------------------------

#
# Setup environment from cron job
#
. /home/oracle/scripts/.bash_profile_cron $1 $2

# Check if PMON is running
if [ `ps -ef | grep ora_pmon_$ORACLE_SID | grep -v grep | wc -l` -eq 0 ]
then
    echo "Oracle is not running"
    exit
fi

echo "Oracle is running"

# Write current database role to variable
CURRENT_ROLE=`cat $DB_ROLE_FILE`
echo Current role: $CURRENT_ROLE

# Is it PRIMARY?
if [ "$CURRENT_ROLE" = "PRIMARY" ];
then
    echo "This is PRIMARY database. Populate the table with data for the week."
    sqlplus -L -s / as sysdba <<eof
set pages 0
set timing on
insert into dba_monitor.day_redo_volume_gb
(
select trunc(completion_time)                         the_day
      ,count(*)                                       logswitch
      ,round((sum(blocks*block_size)/1024/1024/1024)) redo_volume_gb
  from v\$archived_log
 where trunc(completion_time) > (select max(THE_DAY) from dba_monitor.day_redo_volume_gb)
   and trunc(completion_time) < trunc(sysdate)
   and dest_id = 1
 group by trunc(completion_time)
);
exit
eof

else
    echo "This is not PRIMARY database. Do nothing."
fi
