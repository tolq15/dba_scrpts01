#!/bin/bash

#
# Anatoli Lyssak, 05/31/2012
#===================================================#
# Populate table dba_monitor.ts_mon with data about #
# tablespace sizes                                  #
#===================================================#

#
# Setup environment from cron job
#
# $1 - db name
# $2 - db unique name
. /home/oracle/scripts/.bash_profile_cron $1 $2

# Check if PMON is running
if [ `ps -ef | grep ora_pmon_$ORACLE_SID | grep -v grep | wc -l` -eq 0 ]; then
   echo "Oracle is not running"
   exit
fi

echo "Oracle is running"

# Write current database role to variable
CURRENT_ROLE=`cat $DB_ROLE_FILE`
echo Current role: $CURRENT_ROLE

# Is it PRIMARY?
if [ "$CURRENT_ROLE" = "PRIMARY" ];
then
    echo "This is PRIMARY database. Insert data in the table."

    sqlplus -L -s / as sysdba <<eof2
set pages 0
insert into dba_monitor.ts_mon
(
select sysdate
     , d.tablespace_name
     , d.mbytes - nvl(f.free_mbytes,0)
     , d.mbytes
     , d.total_mbytes
     , 100 - round(100*nvl(f.free_mbytes,0)/d.mbytes,1)
     , extensible_files
  from (select tablespace_name
             , sum(decode (autoextensible, 'NO', bytes,
                                          'YES', maxbytes))/1024/1024 total_mbytes
             , sum(bytes)/1024/1024 mbytes
             , sum(decode (autoextensible, 'NO', 0,
                                          'YES', 1)) extensible_files
         from dba_data_files
         group by tablespace_name) d
     , (select tablespace_name
             , sum(bytes)/1024/1024 free_mbytes
          from dba_free_space
          group by tablespace_name) f
 where d.tablespace_name = f.tablespace_name (+)
UNION
select sysdate
     , d.tablespace_name
     , d.mbytes - nvl(f.free_mbytes,0)
     , d.mbytes
     , d.total_mbytes
     , 100 - round(100*nvl(f.free_mbytes,0)/d.mbytes,1)
     , extensible_files
  from (select tablespace_name
             , sum(decode (autoextensible, 'NO', bytes,
                                          'YES', maxbytes))/1024/1024 total_mbytes
              ,sum(bytes)/1024/1024 mbytes
              ,sum(decode (autoextensible, 'NO', 0,
                                          'YES', 1)) extensible_files
        from   dba_temp_files
        group  by tablespace_name
       ) d
     , (select tablespace_name
              ,sum(bytes_free)/1024/1024 free_mbytes
        from   v\$temp_space_header
        group  by tablespace_name
       ) f
 where d.tablespace_name = f.tablespace_name (+)
);
exit
eof2
else
    echo "This is not PRIMARY database. Did nothing."
fi
