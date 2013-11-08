#!/bin/bash

#
# Setup environment from cron job
#
. /home/oracle/scripts/.bash_profile_cron $1 $2

cd $WORKING_DIR

# Check if PMON is running
if [ `ps -ef | grep ora_pmon_$ORACLE_SID | grep -v grep | wc -l` -eq 0 ]; then
   echo "Oracle is not running"
   exit
fi

echo "Oracle is running"

# Check database role
CURRENT_ROLE=$(sqlplus -s / as sysdba <<EOF
set feed off
set head off
set pages 0
select DATABASE_ROLE||'+'||OPEN_MODE from v\$database;
exit
EOF
)

# Is it PRIMARY?
if [ "$CURRENT_ROLE" != "PRIMARY+READ WRITE" ]
then
    # No.
    echo "This is STANDBY database. This script should run on PRIMARY only."
    echo "Or this is PRIMARY database MOUNTED only. Do nothing."

    # Send e-mail

    exit
fi

echo "This is PRIMARY database. Let's create pictures."

host_name=`hostname`

#
# Create list of the tablespaces
#
TS_LIST=$(sqlplus -s / as sysdba <<EOF
set feed off
set head off
set pages 0
select name from v\$tablespace where name not in ('UNDOTBS1','TEMP') order by 1;
exit
EOF
)

#
# Generate picture for the TS
#
for TS in $TS_LIST;
do
    echo Tablespace $TS SID: $1 Days: $3
    #perl -I/home/oracle/tolq/ChartDirector/lib ./tablespace_pic.pl -sid $1 -ts $TS -days $3
    perl -I/home/oracle/tolq/ChartDirector/lib ./tablespace_pic.pl -ts $TS -days $3

    #
    # Send e-mail with attached pictures
    #
    (echo "There should be one attachment with Space Allocation picture for tablespace $TS";uuencode ./pictures/${1}_${TS}_space.png ${1}_${TS}_space.png) | mailx -s "Space Allocation Picture for database $1 from server $host_name in $GE0_LOCATION"  $DBA_EMAIL

done
