#!/bin/bash

# Setup environment from cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2

#EMAIL=york.zhang@nuance.com
EMAIL="NOD-Database-Services@nuance.com,NOC_Sun@nuance.com,NOC_India@nuance.com,opsDBAdmin@mobile.asp.nuance.com"
SESSIONS_MAX=$3
RPT_FILE=/tmp/active_session_rpt.txt

# Find number of active sessions for application accounts
APP_ACTIVE_SESSIONS=$(sqlplus -s / as sysdba <<EOF
set feed off
set head off
set pages 0
select count(*) from v\$session
where status = 'ACTIVE';
exit
EOF
)

# Write to log file
echo Database $1 on server `hostname` has $APP_ACTIVE_SESSIONS active application sessions.
echo Maximum set to $SESSIONS_MAX.

# Check if there are too many sessions and send e-mail if needed
if (( APP_ACTIVE_SESSIONS > SESSIONS_MAX ))
then
    # Send e-mail
    echo "Database $1 on server `hostname` has $APP_ACTIVE_SESSIONS active application sessions" >$RPT_FILE
    echo "" >>$RPT_FILE
    echo " NOC: If you got this alarm >= 2 times in 3 minutes,  please call NVC DBA Anatoli at 339-227-5953 or  DBA york zhang at 408-3293397  or call Saurabh at 408-429-5984" >> $RPT_FILE
sqlplus -s "/ as sysdba" << SQLRUNNING >> $RPT_FILE
  SET SERVEROUTPUT ON SIZE 100000
  SET PAGESIZE 0
  SET HEADING OFF
  col event format a50
  select status, count(*) from v\$session group by status;
  
 select 'max_process_limit' max_process_limit, value from v\$parameter where name='processes'  
     union
   select 'current_process_num' , to_char(count(*))  current_process from v\$process;

 select SQL_ID, event, count(1) from gv\$session group by SQL_ID, event order by 3;
  select a.sql_text, count(*), a.sql_id from v\$sqlarea a,
  v\$session b
  where a.hash_value = b.sql_hash_value
  and username not in ('SYSTEM','SYS')
  and b.status='ACTIVE'
  group by a.sql_id, a.sql_text
  order by count(*)
  ;
  
  EXIT
SQLRUNNING
    cat $RPT_FILE | mailx -s "Database $1 on server `hostname` has $APP_ACTIVE_SESSIONS active application sessions ." $EMAIL
fi


# Additional Audit Trail Logging of data
LOGFILE=/home/oracle/scripts/log/check_active_sessions_audit.log
TMPFILE=/tmp/check_active_sessions_audit.out

sqlplus -s "/ as sysdba" @/home/oracle/scripts/check_active_sessions_audit.sql > $TMPFILE

if [[ -s $LOGFILE ]]; then

LOGCOUNT=`wc -l $LOGFILE|cut -d" " -f1`
let MOD=$LOGCOUNT%50

 if [[ $MOD == 0 ]];then
  cat $TMPFILE | head -4                >> $LOGFILE
 else
  cat $TMPFILE | tail -2 |head -1       >> $LOGFILE
 fi
else
cat $TMPFILE | head -4                  >> $LOGFILE
fi
