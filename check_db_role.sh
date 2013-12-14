#!/bin/bash

# Script
# 1. Check current database role (Primary or Standby).
# 2. Write role into output file so other scrips can get role from file, not from database.
# 3. Send e-mail if database role changed, indicating possible failover.
#
# All environment settings done from cron job:
# * * * * * . /home/oracle/scripts/.bash_profile_cron dbname db_unique_name;/home/oracle/scripts/check_db_role.sh > /home/oracle/scripts/log/check_db_role_dbname.log

# Write current database role to variable
CURRENT_ROLE=$(sqlplus -L -s / as sysdba <<EOF
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

# find old role
if [[ -e $DB_ROLE_FILE ]]
then
    OLD_ROLE=`cat $DB_ROLE_FILE`
else
    # It will be here when this script run for the first time.
    # Create $DB_ROLE_FILE manually to avoid this.
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
    echo $CURRENT_ROLE | cat > $DB_ROLE_FILE

    # Write log file
    echo Database $ORACLE_SID: Role on server $ORACLE_HOST_NAME changed from $OLD_ROLE to $CURRENT_ROLE.

    # Send e-mail
    echo Database $ORACLE_SID: Role on server $ORACLE_HOST_NAME changed from $OLD_ROLE to $CURRENT_ROLE. | mailx -s "Database $ORACLE_SID: Possible failover." $DBA_EMAIL
fi

# Set new status file timestamp
touch $DB_ROLE_FILE
