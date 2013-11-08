#!/bin/bash

# Setup environment for cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2

# Prepare log file name with time stamp
LOG_FILE=/home/oracle/scripts/log/Arch_delete_$1_$THE_TIME.log

# Only one such script should run at a time
if [ `ps -ef | grep "Arch_delete_$1" | grep -v grep | wc -l` -eq 0 ]
then
    echo "Start backup Arch_delete_$1"
    rman TARGET / log=$LOG_FILE <<EORMAN
connect catalog $RMAN_LOGIN
run {
delete noprompt archivelog all completed before 'sysdate-1/2';
crosscheck archivelog all;
delete noprompt expired archivelog all;
delete noprompt archivelog all backed up 1 times to device type disk;
}
exit;
EORMAN
else
    echo "One script Arch_delete_$1 is running already"
fi
