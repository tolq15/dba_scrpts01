#!/usr/bin/perl -w

#=====================================================================================#
# This script reads Oracle alert log file:                                            #
# $ORACLE_BASE/diag/rdbms/$ORACLE_UNQNAME/$ORACLE_SID/trace/alert_$ORACLE_SID.log     #
# starting from last row backwards untill timestamp stored in configuration file.     #
# Parameter:                                                                          #
# -sid database_name;                                                                 #
#                                                                                     #
# Crontab command (example):                                                          #
# 2,7,12,17,22,27,32,37,42,47,52,57 * * * *                                           #
#    /home/oracle/scripts/alert_monitor.pl -sid xxxxxxxx                              #
#   > /home/oracle/scripts/log/alert_monitor_xxxxxxxx.log 2>&1                        #
#                                                                                     #
# Script reads corresponding section (based on DB name and server name) from          #
# configuration file ./config/alert_monitor.conf, where 'config' is                   #
# subdirectory of the script home directory.                                          #
#............................... configuration file ..................................#
# [STPHORACLEDB05_NVCSEA3]
# # List messages which can be ignored:
# # WARNING: inbound connection timed out (ORA-3136)
# # ORA-1652: unable to extend temp segment
# # ORA-28500: connection from ORACLE to a non-Oracle system returned this message:
# # ORA-00235: control file read without a lock inconsistent due to concurrent update
# alert_log=/opt/oracle/diag/rdbms/nvcsea3b/nvcsea3/trace/alert_nvcsea3.log
# errors_exclude=(ORA-3136|ORA-1654|ORA-28500|ORA-00235)
# errors_include=(ORA-|TNS-|crash|Error)
# to=opsDBAdmin@mobile.asp.nuance.com
# smtp=stoam02.ksea.net
# timestamp=Sun Apr 12 07:29:48 2009
#
# [STPHORACLEDB05_SDAVZSE1]
# # List messages which can be ignored:
# # WARNING: inbound connection timed out (ORA-3136)
# # ORA-1652: unable to extend temp segment
# # ORA-28500: connection from ORACLE to a non-Oracle system returned this message:
# # ORA-00235: control file read without a lock inconsistent due to concurrent update
# alert_log=/opt/oracle/diag/rdbms/nvcsea3b/nvcsea3/trace/alert_sdavzse1.log
# errors_exclude=(ORA-3136|ORA-1654|ORA-28500|ORA-00060|ORA-00235)
# errors_include=(ORA-|TNS-|crash|Error)
# to=opsDBAdmin@mobile.asp.nuance.com
# smtp=stoam02.ksea.net
# timestamp=Sun Apr 12 07:29:48 2009
#.....................................................................................#
#                                                                                     #
# After reading all messages, generated in last 6 minutes, the messages are filtered  #
# using 'include' and 'exclude' patterns. Result is written to log file and e-mailed  #
# to DBA team.                                                                        #
#=====================================================================================#

use strict;
use warnings;
use File::Basename;
use File::ReadBackwards;
use FileHandle;
use Config::IniFiles;
use Mail::Sender;

use lib $ENV{WORKING_DIR};
require $ENV{MY_LIBRARY};

#--------------------------------------------------------------#
# DB name and server name should be UPPER case. This is needed #
# to read corresponding section from configuration file        #
#--------------------------------------------------------------#
my $db_name        = uc $ENV{ORACLE_SID};
my $server_name    = uc $ENV{ORACLE_HOST_NAME};
my $config_db_name = $server_name.'_'.$db_name;

#----------------------------------------------------#
# Call procedure from my_library.pl                  #
# Get file names, check for double execution         #
# and return reference hash with config parameters   #
# It does not check for double execution on Windows. #
#----------------------------------------------------#
my ($double_exec, $config_params_ref, $script_dir)
    = SetConfCheckDouble($db_name, 'SCRIPT_DIR', 'CONFIG_FILE');

#------------------------------------------#
# Read configuration file and check format #
#------------------------------------------#
my $alert_log        = $config_params_ref->{$config_db_name}{'alert_log'};
my $errors_include   = $config_params_ref->{$config_db_name}{'errors_include'};
my $errors_exclude   = $config_params_ref->{$config_db_name}{'errors_exclude'};
my $oldest_timestamp = $config_params_ref->{$config_db_name}{'timestamp'};
if (    ( !defined $alert_log      )
     or ( !defined $errors_include )
     or ( !defined $errors_exclude )
   )
{
    print "Check configuration file. Some parameter was not defined.\n";
    exit 1;
}

# In case if there is no new timestamps in log file.
# Timestamp to write in configuration file.
my $timestamp2remember = $oldest_timestamp;

# Flag for first timestamp
my $the_first_time = 1;

# Oracle alert timestamp format: Sun Apr 12 07:29:48 2009
my $timestamp_pattern = "^(Sun|Mon|Tue|Wed|Thu|Fri|Sat) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\\s{1,2}\\d{1,2} \\d{2}:\\d{2}:\\d{2} \\d{4}\$";

#--------------------------------#
# Open log file to read backward #
#--------------------------------#
tie *ALERT, 'File::ReadBackwards', $alert_log
    or die "Can't read $alert_log $!" ;

#--------------------------------------------------#
# Read the file line by line starting from the end #
#--------------------------------------------------#
my $message = '';
while( <ALERT> )
{
    my $alert_line = $_;

    #-----------------------------#
    # Process line with timestamp #
    #-----------------------------#
    if ($alert_line =~ m/$timestamp_pattern/)
    {
        #------------------------------------------------------#
        # This is the last loop if we reached oldest timestamp #
        #------------------------------------------------------#
        last if ($alert_line =~ m/^$oldest_timestamp$/);

        # Find and remember the first time stamp we read
        if ($the_first_time)
        {
            # Write it into configuration file at the end of the script
            $the_first_time     = 0;
            $timestamp2remember = $alert_line;
            # for correct compare with $oldest_timestamp
            chomp $timestamp2remember;
        }
        next;
    }

    #==========================================#
    # This is not a timestamp.                 #
    # Check for errors to include and exclude. #
    #==========================================#
    if (    ($alert_line =~ m/$errors_include/i)
        and ($alert_line !~ m/$errors_exclude/i))
    {
        $message = $alert_line . $message;
    }
}   # while( <ALERT> )

#----------------------------------------------------#
# Send e-mail if there are new errors.               #
#----------------------------------------------------#
if ( ( $message ne '' ) and ( $oldest_timestamp ne $timestamp2remember ))
{
    my $subject = "Errors in Oracle Alert Log $db_name on $server_name.";

    # Print to output file and error message in chronological order
    $message = "Errors found in time range\n$oldest_timestamp\n$timestamp2remember\n"
              . $message;
    SendAlert ( $server_name, $db_name, $subject, $message );
}
else
{
    # If there are no alerts in alert log file, this should be the only
    # output line in the script log:
    if ($oldest_timestamp eq $timestamp2remember)
    {
        print "No errors found since time\n$oldest_timestamp\n";
    }
    else
    {
        print "No errors found in time range\n$oldest_timestamp\n$timestamp2remember\n";
    }
}

#-------------------------------------------------#
# All is done. Now we can overwrite old timestamp #
# in configuration file                           #
#-------------------------------------------------#
RewriteConfigFileNew ($config_db_name, $config_params_ref, 'timestamp', $timestamp2remember) || die "ERROR: rewriting Config File: @Config::IniFiles::errors\n";

exit;
