#!/bin/bash -
#sync_gg_files.sh
#
# This script is used to sync files from one server to another using rsync
# 
# NOTES:  It can be upgraded to be more versatile by not hard coding the paths in the script
#
# Pre-req : It is assumed that ssh password less authentication has been setup
#
#=================

# Setup environment for cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2

WORKFILE=/tmp/$$_sync.tmp

cd /home/oracle/scripts/

#Check if Primary DB 
sqlplus -s / as sysdba <<eof1 > $WORKFILE
set pages 0
select DATABASE_ROLE, OPEN_MODE from v\$database;
exit
eof1

if [ `grep -o "PRIMARY" $WORKFILE | grep -v grep | wc -l` -eq 1 ]; then
   if [ `grep -o "READ WRITE" $WORKFILE | grep -v grep | wc -l` -eq 1 ]; then
      echo "This is PRIMARY database. Syncing Goldengate dirdat"
      #rsync -avz -e ssh STPHORACLEDB05:scott/ /opt/oracle/product/gg/dirdat/
      cd $GGATE
      rsync -avz -e ssh --delete dirdat/ STPHORACLEDB05:/opt/oracle/product/gg/dirdat/
   fi
fi

rm $WORKFILE

