#!/bin/bash

# Setup environment for cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2

# Prepare log file name with time stamp
LOG_FILE=/home/oracle/scripts/log/Arch_emerg_$1_$THE_TIME.log

rman TARGET / log=$LOG_FILE <<EORMAN
connect catalog $RMAN_LOGIN
run {
crosscheck archivelog all;
delete noprompt archivelog all backed up 1 times to device type disk;
}
exit;
EORMAN
