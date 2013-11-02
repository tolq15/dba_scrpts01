I plan to put about 20 scripts in this repository. Most of these scripts I'm using in production environment.
Most of the scripts are in Perl, some scripts are in Python and Shell.
All scripts write log files in directory ./log, and send e-mail to DBA in case of emergency.
We use Oracle DataGuard as disaster recovery. Almost all scrips check database role because supposed to run on
Primary database.

THIS IS WORK IN PROGRESS.

1. Oracle Alert Log Monitor Scripts
1.1. alert_monitor.pl
    This script connects to running Oracle instance and select alerts from table x$dbgalertext (for Oracle 11g and later).
    This table should be recycled in reqular bases because it can grow very fast and select statement will run for
    long time. Usualy it can be problem on Test/QA environments. Also this require database up and running.
    If your database crashs you will never receive alert, so there should be special script to monitor database.
1.2. alert_monitor_rb.pl
    This scrip read alert log file backward (from last line untill line with timestam stored in config file). In this
    case script execution time does not depend upon log file size. Also you will receive all alert, even if database is
    down, becase connection to the database is not requered.

2. Oracle Tablespace Monitor Script
3. Linux Disk Space Monitor Script
