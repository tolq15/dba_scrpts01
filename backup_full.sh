#!/bin/bash

# Setup environment for cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2
#
# Remove the last full backup first, otherwise it will fill up the filesystem.
#
#if [ $1 = "nvcsea3" ];
#then
    cd /oracle7/orabackup/nvcsea3
    rm bkfull_*.bus
    find ./ -name "arch_*.bus" -mtime +1 -exec rm {} \;
#fi
#
cd /home/oracle/scripts

# Prepare log file name with time stamp
LOG_FILE=$WORKING_DIR/log/Full_$1_`date +%Y%m%d%H%M%S`.log

# Check to see if there is any full backup running or not ?
if [ `ps -ef | rep rman | grep "Full_$1" | grep -v grep | wc -l` -ne 0 ]
then
    echo "Full Backup is already Running. So exit."
    exit;
fi

# Write current database role to variable
CURRENT_ROLE=`cat $DB_ROLE_FILE`
echo Current role: $CURRENT_ROLE

# Is it PRIMARY?
if [ "$CURRENT_ROLE" != "PRIMARY" ];
then
    echo $CURRENT_ROLE
    echo "This is Physical Standby database. Let's do backup."

    rman TARGET / log=$LOG_FILE <<EORMAN
connect catalog $RMAN_LOGIN
resync catalog;
run {
crosscheck backup;
crosscheck archivelog all;
sql 'alter database backup controlfile to trace';
backup as copy current controlfile
   format '/oracle4/orabackup/$1/%U.ctl';

allocate channel ora1 device type disk format '/oracle4/orabackup/$1/bkfull_%s_%p_%t.bus';
allocate channel ora2 device type disk format '/oracle4/orabackup/$1/bkfull_%s_%p_%t.bus';
allocate channel ora3 device type disk format '/oracle4/orabackup/$1/bkfull_%s_%p_%t.bus';
allocate channel ora4 device type disk format '/oracle4/orabackup/$1/bkfull_%s_%p_%t.bus';
backup as compressed backupset 
tag 'Full_$1_$THE_TIME'
database;

backup as compressed backupset
   tag 'Archivelog_$1'
   archivelog all not backed up;
delete noprompt archivelog all backed up 1 times to device type disk;
delete noprompt obsolete ;
}
resync catalog;
EXIT;
EORMAN

   # Check status of the backup finished 2 minute ago
   STATUS=$(sqlplus -s / as sysdba <<EOF
set feed off
set head off
set pages 0
select status
  from v\$rman_backup_job_details
 where input_type = 'DB FULL'
   and end_time > sysdate - 5/1440;
exit;
EOF
)

   echo "Backup Status: $STATUS"

   # Do not send e-mail if status is 'COMPLETE'
   if [ "$STATUS" != "COMPLETED" -o `egrep RMAN-\|ORA- $LOG_FILE | wc -l` -ne 0 ];
   then
      egrep RMAN-\|ORA- $LOG_FILE | egrep -v RMAN-08120\|RMAN-08137\|RMAN-08138 | mail -s "$STATUS: Full Backup for database $1 on server $HOSTNAME" $DBA_EMAIL
   fi

else
    echo "This is PRIMARY database. Just take the backup of the controlfile and spfile."
    rman TARGET / log=$LOG_FILE <<EORMAN
connect catalog $RMAN_LOGIN
resync catalog;
run {
sql 'alter database backup controlfile to trace';
backup as copy current controlfile
   format '/oracle4/orabackup/$1/%U.ctl';
}
EXIT;
EORMAN

fi
