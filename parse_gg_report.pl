#!/usr/bin/perl -w

#===========================================================#
# Script to parse GG report file
# 03/02/2013 Created from
# Report time should be set in GG param file in line like
# "Report at 10:00"
# grep string:
# egrep 'Report at 2013-[0-9]{2}-[0-9]{2} 10:00:0[0-9] ' PUMP_24.rpt | sort
#
# Table was created as:
# create table dba_monitor.gg_activity1
# (
#  table_name  varchar2(30),
#  report_date date,
#  since_date  date,
#  run_date    date,
#  inserts     number,
#  updates     number,
#  deletes     number
# );
#===========================================================#

use strict;
use Cwd;
use Getopt::Long;
use File::Basename;
use DBI;
use DBD::Oracle qw(:ora_session_modes);
use FileHandle;
use Config::IniFiles;
use Time::Local;
use Mail::Sender;

use lib $ENV{WORKING_DIR};
require $ENV{MY_LIBRARY};

my $timestamp2remember;

# Get hostname. This value is used to access config file.
chomp (my $server_name = `hostname`);

#-------------------------------------------#
# Check and Parse required input parameters #
#-------------------------------------------#
my $db_name = uc $ENV{ORACLE_SID};

# Connect to the database
my $dbh = Connect2Oracle ($db_name);

#
# Check for primary
#
if ( CheckDBRole($db_name) !~ m/PRIMARY/ )
{
    print "CheckDBRole did not return PRIMARY\n";
    exit 1;
}

# Prepare SQL
my $sql01 = qq{ INSERT INTO dba_monitor.gg_activity1
              VALUES ( ?
                       , to_date(?,'yyyy-mm-dd hh24:mi:ss')
                       , to_date(?,'yyyy-mm-dd hh24:mi:ss')
                       , sysdate, ?, ?, ? ) };
my $sth = $dbh->prepare( $sql01 );

#-------------------------------------------------------------------#
# Database name in UPPER case should be found in configuration file #
#-------------------------------------------------------------------#
$db_name     = uc $db_name;
$server_name = uc $server_name;

# This is needed to read correspondent section from configuration file
my $unique_db_name = $server_name.'_'.$db_name;

#----------------------------------------------------#
# Call procedure from my_library.pl                  #
# Get file names, check for double execution         #
# and return reference hash with config parameters   #
# It does not check for double execution on Windows. #
#----------------------------------------------------#
my $config_params_ref = GetConfig();

#------------------------------------------#
# Read configuration file and check format #
# report time parameter should be like 10:00 #
#------------------------------------------#
my $gg_report_file_ini = $config_params_ref->{$unique_db_name}{'gg_report_file_ini'};
my $report_directory   = $config_params_ref->{$unique_db_name}{'report_directory'};
my $search_string      = $config_params_ref->{$unique_db_name}{'search_string'};
my $tables             = $config_params_ref->{$unique_db_name}{'tables'};
my $old_timestamp      = $config_params_ref->{$unique_db_name}{'timestamp'};
if (   ( !defined $gg_report_file_ini )
    or ( !defined $search_string      )
    or ( !defined $report_directory   )
    or ( !defined $tables             ))
{
    print "Check configuration file. Some parameters were not configured.\n";
    exit 1;
}

my $report_ext = '.rpt';
my @tables = split (/ /, $tables);

# Go to GG report directory
my $current_dir = getcwd;
chdir $report_directory;

# Create list of report files
my $temp = $gg_report_file_ini . '*' . $report_ext;
my @report_files = glob ("$temp");

#-----------------------------------------------------------#
# Go through report files from ...9 to ...0 to collect info #
#-----------------------------------------------------------#
foreach (reverse @report_files)
{
    # Generate report file name
    my $the_report_file = $_;
    search_report_file ($the_report_file, $search_string);
}

# Go to oracle script directory
chdir $current_dir;

# Write new timestamp into configuration file
RewriteConfigFile ($unique_db_name, $config_params_ref, 'timestamp', $timestamp2remember)
    or die "ERROR: rewriting Config File: @Config::IniFiles::errors\n";

exit;



#xxxxxxxxxxxxxxx#
#  SUBROUTINS   #
#xxxxxxxxxxxxxxx#

#=====================================================#
# Extract data from report file and write to database #
#=====================================================#
sub search_report_file
{
    my ($file_name, $pattern) = @_;

    my $info_begin = 0; # flag to start info collection
    my $all_lines  = '';
    my $begin;
    my $since;

    # Open and read file line by line
    open (FILE, $file_name);
    while (my $line =  <FILE>)
    {
        if ($info_begin)
        {
            # Is it the end of info?
            if ( $line =~ /Run Time Warnings/ )
            {
                # Yes
                $info_begin = 0;

                # Analyze collected details using multi-line regexp.
                # '.*?' and 'scgi' are the most importent here.
                while ($all_lines =~ m/(SPEECH_OWNER.\w+):.*?inserts:\s+(\d+).*?updates:\s+(\d+).*?deletes:\s+(\d+)/scgi)
                {
                    printf "%26s %19s %19s %10d %10d %10d\n", $1, $begin, $since, $2, $3, $4;
                    # Insert search results into Oracle table. Autocommit is in effect.
                    eval
                    {
                        $sth->bind_param(1, $1);
                        $sth->bind_param(2, $begin);
                        $sth->bind_param(3, $since);
                        $sth->bind_param(4, $2);
                        $sth->bind_param(5, $3);
                        $sth->bind_param(6, $4);
                        $sth->execute();
                    };
                    if ( $@ )
                    {
                        warn "Database error: $DBI::errstr\n";
                        $dbh->rollback(); #just die if rollback is failing
                    }
                }

                # Preapare to next search
                $all_lines = '';
            }
            else
            {
                # Collect all details for futher analyze.
                $all_lines .= $line;
            }
        }
        else
        {
            # Skip everything untill 'Report at 2013-...'
            if ( $line =~ /$pattern/ )
            {
                $begin      = $1;
                $since      = $2;
                # New timestamp
                $timestamp2remember = substr $begin, 0, 10;
                if ($timestamp2remember le $old_timestamp)
                {
                    #print "$file_name, $timestamp2remember\n";
                    next;
                }
                else
                {
                    $info_begin = 1;
                }
            }
        }
    }
}

