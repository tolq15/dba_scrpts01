#!/usr/bin/perl -w

#===========================================================#
# Script to monitor GoldenGate log file (ggserr.log).       #
# 02/01/2013 Created from alert_monitoring.pl from Enerflex #
#===========================================================#

use strict;
use Getopt::Long;
use File::Basename;
use File::ReadBackwards;
use FileHandle;
use Config::IniFiles;
use Time::Local;
use Mail::Sender;

use lib "/home/oracle/scripts";
require 'my_library.pl';

my $message = '';

# Get hostname. This value is used to access config file.
chomp (my $server_name = `hostname`);

#-------------------------------------------#
# Check and Parse required input parameters #
#-------------------------------------------#
my $db_name;

GetOptions('sid:s', \$db_name);
die "ERROR: Database name required\n" if (!defined $db_name);

#-------------------------------------------------------------------#
# Database name in UPPER case should be found in configuration file #
#-------------------------------------------------------------------#
$db_name     = uc $db_name;
$server_name = uc $server_name;

# This is needed to read correspondent section from configuration file
my $unique_db_name = $server_name.'_'.$db_name;

# Flag for first timestamp
my $the_first_time = 1;

# GoldenGate timestamp: 2013-02-01 17:00:15
my $timestamp_pattern = "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2} ";

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
my $ggserr_log       = $config_params_ref->{$unique_db_name}{'ggserr_log'};
my $errors_include   = $config_params_ref->{$unique_db_name}{'errors_include'};
my $errors_exclude   = $config_params_ref->{$unique_db_name}{'errors_exclude'};
my $oldest_timestamp = $config_params_ref->{$unique_db_name}{'timestamp'};
if (( !defined $errors_include ) or ( !defined $errors_exclude ))
{
    print "Check configuration file. INCLUDE or EXCLUDE does not configured.\n";
    exit 1;
}

# In case if there is no new timestamps in log file.
# Timestamp to write in configuration file.
my $timestamp2remember = $oldest_timestamp;

#--------------------------------#
# Open log file to read backward #
#--------------------------------#
tie *GGSERR, 'File::ReadBackwards', $ggserr_log
    or die "Can't read $ggserr_log $!" ;

#--------------------------------------------------#
# Read the file line by line starting from the end #
#--------------------------------------------------#
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
        print       $ggserr_line;
        $message .= $ggserr_line;
    }

}   # while( <GGSERR> )

#----------------------------------------------------#
# Send e-mail if there are errors                    #
# 'to' and 'smtp' are hard-coded                     #
# These values should be moved to configuration file #
#----------------------------------------------------#
if ( $message ne '')
{
    # Print to output file and error message
    $message .= "Errors found in time range\n$oldest_timestamp\n$timestamp2remember\n";
    print       "Errors found in time range\n$oldest_timestamp\n$timestamp2remember\n";

    my $sender = new Mail::Sender;
    (ref ($sender->MailMsg
          (
           {
            to      => 'opsDBAdmin@mobile.asp.nuance.com',
            from    => 'oracle@'.$server_name,
            smtp    => 'stoam02.ksea.net',
            subject => "Errors in GoldenGate Log $db_name on $server_name.",
            msg     => $message
           }
          )
         )  and print "Mail sent OK.\n"
    )    or die "Mail Sender Error: $Mail::Sender::Error\n";
}
else
{
    # If there are no alerts in alert log file, this should be the only
    # output line in the script log:
    print "No errors found in time range\n$oldest_timestamp\n$timestamp2remember\n";
}

#-------------------------------------------------#
# All is done. Now we can overwrite old timestamp #
# in configuration file                           #
#-------------------------------------------------#
RewriteConfigFileNew ($unique_db_name, $config_params_ref, 'timestamp', $timestamp2remember) || die "ERROR: rewriting Config File: @Config::IniFiles::errors\n";

exit;
