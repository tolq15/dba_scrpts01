#!/bin/bash

# Setup environment for cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2

# Prepare log file name with time stamp
LOG_FILE=/home/oracle/scripts/log/Diff_$1_$THE_TIME.log

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
    echo "This is PRIMARY database. Let's do backup."

    # Start backup
    rman TARGET / log=$LOG_FILE <<EORMAN
connect catalog $RMAN_LOGIN
run {
sql 'alter database backup controlfile to trace';
backup as copy current controlfile
   format '$BACKUP_HOME/$1/%U.ctl';
backup as compressed backupset
   device type disk
   format '$BACKUP_HOME/$1/spfile_%s_%p_%t.bus'
   tag 'Spfile_$1_$THE_TIME'
   spfile;
backup as compressed backupset
   device type disk
   format '$BACKUP_HOME/$1/bkinc1_%s_%p_%t.bus'
   tag 'Diff_$1_$THE_TIME'
   incremental level 1 database;
delete noprompt obsolete;
sql 'alter system archive log current';
backup as compressed backupset
   device type disk
   format '$BACKUP_HOME/$1/arch_%d_%s.bus'
   tag 'Arch_$1_$THE_TIME'
   archivelog all not backed up;
# See script backup_archivelog_delete.sh
# delete noprompt archivelog all backed up 1 times to device type disk;
}
EXIT;
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
 where input_type = 'DB INCR'
   and end_time   = (select max(end_time)
                       from v\$rman_backup_job_details
                      where input_type = 'DB INCR');
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
        egrep RMAN-\|ORA- $LOG_FILE | egrep -v RMAN-08120\|RMAN-08137\|RMAN-08138 | mail -s "$STATUS: Incremental Backup for database $1 on server $HOSTNAME in $GE0_LOCATION" $DBA_EMAIL
    fi

else
    echo "This is not PRIMARY database. Skip incremental backup."
fi
