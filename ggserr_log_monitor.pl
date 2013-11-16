#!/usr/bin/perl -w

#===========================================================#
# Script to monitor GoldenGate log file (ggserr.log).       #
# 02/01/2013 Created from alert_monitoring.pl from Enerflex #
#===========================================================#

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
    = SetConfCheckDouble($db_name, 'SCRIPT_DIR','CONFIG_FILE');

#------------------------------------------#
# Read configuration file and check format #
#------------------------------------------#
my $ggserr_log       = $config_params_ref->{$config_db_name}{'ggserr_log'};
my $errors_include   = $config_params_ref->{$config_db_name}{'errors_include'};
my $errors_exclude   = $config_params_ref->{$config_db_name}{'errors_exclude'};
my $oldest_timestamp = $config_params_ref->{$config_db_name}{'timestamp'};
if (    ( !defined $ggserr_log     )
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

# GoldenGate timestamp: 2013-02-01 17:00:15
my $timestamp_pattern = "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2} ";

#--------------------------------#
# Open log file to read backward #
#--------------------------------#
tie *GGSERR, 'File::ReadBackwards', $ggserr_log
    or die "Can't read $ggserr_log $!" ;

#--------------------------------------------------#
# Read the file line by line starting from the end #
#--------------------------------------------------#
my $message = '';
while( <GGSERR> )
{
    my $ggserr_line = $_;

    #------------------------------------------------------#
    # This is the last loop if we reached oldest timestamp #
    #------------------------------------------------------#
    last if ($ggserr_line =~ m/$oldest_timestamp/);

    # Find and remember the first timestamp we read
    if ($the_first_time)
    {
        # Write it into configuration file at the end of the script.
        # Extract timestamp from the log line: first 19 chars
        if ($ggserr_line =~ m/$timestamp_pattern/)
        {
            $timestamp2remember = substr $ggserr_line, 0, 19;
            $the_first_time     = 0;
        }
    }

    #==========================================#
    # This is not a timestamp.                 #
    # Check for errors to include and exclude. #
    #==========================================#
    if (    ($ggserr_line =~ m/$errors_include/i)
        and ($ggserr_line !~ m/$errors_exclude/i))
    {
        # Print to output file and error message
        $message = $ggserr_line . $message;
    }
}   # while( <GGSERR> )

#----------------------------------------------------#
# Send e-mail if there are new errors.               #
#----------------------------------------------------#
if ( ( $message ne '' ) and ( $oldest_timestamp ne $timestamp2remember ))
{
    my $subject = "Errors in GoldenGate Log $db_name on $server_name.";

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
