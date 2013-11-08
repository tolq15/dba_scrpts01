#!/bin/bash

# Setup environment for cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2

# Prepare log file name with time stamp
LOG_FILE=/home/oracle/scripts/log/Arch_$1_$THE_TIME.log

# Write current database role to variable
CURRENT_ROLE=$(sqlplus -s / as sysdba <<EOF
set feed off
set head off
set pages 0
select DATABASE_ROLE from v\$database;
exit
EOF
)

# Is it PRIMARY?
if [ "$CURRENT_ROLE" = "PRIMARY" ]
then
    echo "This is PRIMARY database."
    rman TARGET / log=$LOG_FILE <<EORMAN
connect catalog $RMAN_LOGIN
run {
delete noprompt archivelog all completed before 'sysdate-1/2';
crosscheck archivelog all;
}
exit;
EORMAN

else
    echo "This is STANDBY database. Take archivelog backups."

# Delete backups taken 2 days old.
find /oracle4/orabackup/$1 -mtime +2 -exec rm {} \;

#
rman TARGET / log=$LOG_FILE APPEND <<EORMAN
connect catalog $RMAN_LOGIN
run {
crosscheck archivelog all;
crosscheck backup;

allocate channel ora1 device type disk format '/oracle4/orabackup/$1/arch_%d_%s.bus';
allocate channel ora2 device type disk format '/oracle4/orabackup/$1/arch_%d_%s.bus';
allocate channel ora3 device type disk format '/oracle4/orabackup/$1/arch_%d_%s.bus';
allocate channel ora4 device type disk format '/oracle4/orabackup/$1/arch_%d_%s.bus';

backup as compressed backupset
tag 'Arch_$1_$THE_TIME'
archivelog all not backed up;
delete noprompt obsolete;
}
exit;
EORMAN


# Check status of the last backup.
# I hope two backups will never run at the same time.
# Check status of the backup finished 1 minute ago
# and remove blank line from output
STATUS=$(sqlplus -s / as sysdba <<EOF
set feed off
set head off
set pages 0
select status
  from v\$rman_backup_job_details
 where input_type = 'ARCHIVELOG'
   and end_time   = (select max(end_time)
                       from v\$rman_backup_job_details
                      where input_type = 'ARCHIVELOG');
exit;
EOF
)

echo "Backup Status: $STATUS"

# Exclude message:
# RMAN-08120: WARNING: archived log not deleted, not yet applied by standby
# RMAN-08137: WARNING: archived log not deleted, needed for standby or upstream capture process
# RMAN-08138: WARNING: archived log not deleted - must create more backups
if [ "$STATUS" != "COMPLETED" -o `egrep RMAN-\|ORA- $LOG_FILE | egrep -v RMAN-08120\|RMAN-08137\|RMAN-08138 | wc -l` -ne 0 ]
then
    egrep RMAN-\|ORA- $LOG_FILE | egrep -v RMAN-08120\|RMAN-08137\|RMAN-08138 | mail -s "$STATUS: Archivelog Backup for database $1 on server $HOSTNAME in $GE0_LOCATION" $DBA_EMAIL
fi
fi
