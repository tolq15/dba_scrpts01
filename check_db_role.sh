#!/bin/bash

# Setup environment from cron job
. /home/oracle/scripts/.bash_profile_cron $1 $2

# Go to working directory
cd /home/oracle/scripts

# Write current database role to variable
CURRENT_ROLE=$(sqlplus -s / as sysdba <<EOF
set feed off
set head off
set pages 0
select DATABASE_ROLE from v\$database;
exit
EOF
)

# Check if connecion to database failed
if [[ "$CURRENT_ROLE" != "PHYSICAL STANDBY" && "$CURRENT_ROLE" != "PRIMARY" ]]
then
    CURRENT_ROLE='UNKNOWN'
fi

#OLD_ROLE=`cat current_db_role_${1}.txt`
if [[ -e current_db_role_${1}.txt ]]
then
    OLD_ROLE=`cat current_db_role_${1}.txt`
else
    OLD_ROLE='NO_STATUS_FILE'
fi

# Write log file
echo "This is current role: $CURRENT_ROLE"
echo "This is old role    : $OLD_ROLE"

# Check if role change
if [ "$CURRENT_ROLE" == "$OLD_ROLE" ]
then
    echo Role is the same. Do nothing.
else
    # Write new role to status file
    echo $CURRENT_ROLE | cat > current_db_role_${1}.txt

    # Write log file
    echo Database $1: Role on server `hostname` changed from $OLD_ROLE to $CURRENT_ROLE.

    # Send e-mail
    echo Database $1: Role on server `hostname` changed from $OLD_ROLE to $CURRENT_ROLE. | mailx -s "Database $1: Possible failover." $DBA_EMAIL
fi

# Set new status file timestamp
touch current_db_role_${1}.txt
