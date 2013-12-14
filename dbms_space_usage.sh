#!/bin/bash

# Setup environment for cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2

cd $WORKING_DIR

#EMAIL=kishore.mohapatra@nuance.com

REPORT=$WORKING_DIR/reports/dbms_space_space_usage.txt

# Write current database role to variable
CURRENT_ROLE=`cat $DB_ROLE_FILE`
echo Current role: $CURRENT_ROLE

# Is it PRIMARY?
if [ "$CURRENT_ROLE" = "PRIMARY" ]
then
    echo "This is PRIMARY database. Let's run the report."

sqlplus -L -s "/ as sysdba" << EOF
set serveroutput on

col fs4b format 999,999,999,999,999
col fs3b format 999,999,999,999,999
col fs2b format 999,999,999,999,999
col fs1b format 999,999,999,999,999
col fullb format 999,999,999,999,999
col unfb format 999,999,999,999,999

declare
 unf number; 
 unfb number; 
 fs1 number; 
 fs1b number; 
 fs2 number; 
 fs2b number; 
 fs3 number; 
 fs3b number; 
 fs4 number; 
 fs4b number; 
 full number; 
 fullb number; 

cursor c1 is
		select owner, segment_name, segment_type from dba_segments
		where owner = 'SPEECH_OWNER'
		and segment_name not like 'SYS%'
		and segment_name not like 'NORMALIZATION_%'
		and segment_name not like 'TEMP%'
		and segment_name not like 'BIN%'
		order by segment_name;

begin 

for c1rec in c1
loop
exit when c1%notfound;
	begin

		dbms_space.space_usage(upper(c1rec.owner),upper(c1rec.segment_name), 
                        	 upper(c1rec.segment_type), 
                        	 unf, unfb, 
                        	 fs1, fs1b, 
                        	 fs2, fs2b, 
                        	 fs3, fs3b, 
                        	 fs4, fs4b, 
                        	 full, fullb
				 ); 

insert into dba_monitor.space_frag (
					run_date , 
					owner, 
					object_name, 
					object_type, 
					free_bl_0_25 , 
					free_byte_0_25 , 
					free_bl_25_50 , 
					free_byte_25_50 , 
					free_bl_50_75 , 
					free_byte_50_75 , 
					free_bl_75_100 , 
					free_byte_75_100 , 
					full_blocks, full_bytes  , 
					unformat_blocks , 
					unformat_bytes
				    )
values				    (
					trunc(sysdate), 
					c1rec.owner, 
					c1rec.segment_name, 
					c1rec.segment_type, 
					TO_CHAR(fs1),
					TO_CHAR(fs1b),
					TO_CHAR(fs2),
					TO_CHAR(fs2b),
					TO_CHAR(fs3),
					TO_CHAR(fs3b),
					TO_CHAR(fs4),
					TO_CHAR(fs4b),
					TO_CHAR(full),
					TO_CHAR(fullb),
					TO_CHAR(unf),
					TO_CHAR(unfb)
				      );

commit;

end; 
end loop;
end;
/ 

col run_date NEW_VALUE rdt
col run_date heading Run_date noprint
col owner heading 'Owner' noprint
col object_name format a20 heading 'Object Name'
col object_type format a15 heading 'Object Type'
col free_bl_0_25 heading 'Blocks 0-25%|Free'
col free_byte_0_25 format 999,999,999,999,999 heading 'Bytes 0-25%|Free'
col free_bl_25_50 format 999,999,999 heading 'Blocks 25-50%|Free'
col free_byte_25_50 format 999,999,999,999,999 heading 'Bytes 25-50%|Free'
col free_bl_50_75 format 999,999,999 heading 'Blocks 50-75%|Free'
col free_byte_50_75 format 999,999,999,999,999 heading 'Bytes 50-75%|Free'
col free_bl_75_100 format 999,999,999 heading 'Blocks 75-100%|Free'
col free_byte_75_100 format 999,999,999,999,999 heading 'Bytes 75-100%|Free'
col full_blocks format 999,999,999 heading 'Full Blocks'
col full_bytes format 999,999,999,999,999 heading 'Full Bytes'
col unformat_blocks format 999,999,999 heading 'Unformatted Blocks'
col unformat_bytes format 999,999,999,999,999 heading 'Unformatted Bytes'

set feedback off
set linesize 300
set pagesize 100

break on run_date on report
compute sum label 'TOTAL' of free_byte_0_25 free_byte_25_50 free_byte_50_75 free_byte_75_100 full_bytes unformat_bytes on report

TTITLE center 'SEATTLE OBJECT SPACE FRAGMENTATION REPORT' skip 2 -
left 'Run_Date :'rdt skip 2

spool $REPORT

select * from dba_monitor.space_frag
where run_date = trunc(sysdate)
order by object_name;

TTITLE off

select round((sum(free_byte_0_25  )*0.00
             +sum(free_byte_25_50 )*0.25
             +sum(free_byte_50_75 )*0.50
             +sum(free_byte_75_100)*0.75)/(1024*1024*1024)) Estimated_Free_GB_MIN,
        round((sum(free_byte_0_25  )*0.25
             +sum(free_byte_25_50 )*0.50
             +sum(free_byte_50_75 )*0.75
             +sum(free_byte_75_100)*1.00)/(1024*1024*1024)) Estimated_Free_GB_MAX
from dba_monitor.space_frag
where run_date = trunc(sysdate);

spool off

EOF

uuencode $REPORT space_fragmentation.rpt |mail -s "DB Space Fragmentation Report" $DBA_EMAIL

else
exit
fi

