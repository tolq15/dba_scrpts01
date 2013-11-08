#!/bin/bash

# Setup environment for cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2

LOGFILE=/home/oracle/scripts/log/dbspace.log
MAILFILE=/tmp/dbspace_mail.out

sqlplus -s "/ as sysdba" @/home/oracle/scripts/dbspace.sql >> $LOGFILE

echo 											 			> $MAILFILE
df -h |egrep "^Filesystem|oracle1|oracle3|oracle5|oracle6"|grep -v dev 						>> $MAILFILE
printf "\n"	 												>> $MAILFILE
ls -lh /oracle*/oradata/nvcsea3/index_ts*.dbf|awk -F" " '{print $5,$9}'|awk -F"_" '{print "x "$1".dbf files"}'|sort|uniq -c 	>> $MAILFILE
ls -lh /oracle*/oradata/nvcsea3/data_ts*.dbf| awk -F" " '{print $5,$9}'|awk -F"_" '{print "x "$1".dbf files"}'|sort|uniq -c	>> $MAILFILE
echo														>> $MAILFILE
cat $LOGFILE | egrep "^DC|^--" | head -2									>> $MAILFILE
cat $LOGFILE | grep "DATA_TS"  | sort -r									>> $MAILFILE
echo														>> $MAILFILE
cat $LOGFILE | grep "INDEX_TS" | sort -r									>> $MAILFILE

cat $MAILFILE | mailx -s "$HOSTNAME : TableSpace Report" opsDBAdmin@mobile.asp.nuance.com
