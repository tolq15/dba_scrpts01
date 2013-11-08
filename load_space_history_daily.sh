#load_space_history_daily.sh
#
# Daily script load object growtch in specific schemas
# Update: 2012/5/28
# Add read from current_db_role.txt
# Update: 2012/7/16
# Remove read from current_db_role.txt. Use query instead
#========================================================

# Setup environment for cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2

# Write current database role to variable
CURRENT_ROLE=$(sqlplus -s / as sysdba <<EOF
set feed off
set head off
set pages 0
select DATABASE_ROLE from v\$database;
exit
EOF
)

if [ "$CURRENT_ROLE" = "PRIMARY" ];
then
    echo "This is PRIMARY database."

#load stats
sqlplus -s / as sysdba <<eof2
set pages 0
insert into dba_monitor.space_history_daily
  select trunc(sysdate) run_date,
  owner, segment_name, NVL(partition_name,'NULL'),
  segment_type, tablespace_name, bytes, extents
  from dba_segments
  where owner = 'SPEECH_OWNER';
COMMIT;
exit
eof2

else
    echo "This is not PRIMARY database. Did nothing."
fi

