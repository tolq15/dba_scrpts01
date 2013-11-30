#!/usr/bin/perl -w

#===========================================================#
# Script to parse GG report file
# 03/11/2013 Created from
# Report time should be set in GG param file in line like
# ....
# ....
# Table was created as:
# create table dba_monitor.gg_activity2
# (
#  report_date date,
#  run_date    date,
#  records     number,
#  rate        number,
#  delta       number
# );
#===========================================================#

use strict;
use warnings;
use Cwd;
use Getopt::Long;
use File::Basename;
use DBI;
use DBD::Oracle qw(:ora_session_modes);
use FileHandle;
use Time::Local;

use lib $ENV{WORKING_DIR};
require $ENV{MY_LIBRARY};

my $db_name     = uc $ENV{ORACLE_SID};
my $server_name = uc $ENV{ORACLE_HOST_NAME};
my $timestamp2remember;

# Connect to the database
my $dbh = Connect2Oracle ($db_name);

#
# Check for primary
#
if ( CheckDBRole($db_name) !~ m/PRIMARY/ )
{
    print "Database role is not PRIMARY. Exit.\n";
    exit 1;
}

# Prepare SQL
my $sql01 = qq{ INSERT INTO dba_monitor.gg_activity2
              VALUES ( to_date(?,'yyyy-mm-dd hh24:mi:ss'), sysdate, ?, ?, ? ) };
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
my $old_timestamp      = $config_params_ref->{$unique_db_name}{'timestamp'};
if (   ( !defined $gg_report_file_ini )
    or ( !defined $search_string      )
    or ( !defined $report_directory   ))
{
    print "Check configuration file. Some parameters were not configured.\n";
    exit 1;
}

my $report_ext = '.rpt';

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
RewriteConfigFile ($unique_db_name, $config_params_ref, 'timestamp', $timestamp2remember);

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

    # Open and read file line by line
    open (FILE, $file_name);
    while (my $line =  <FILE>)
    {
        if ( $line =~ /$pattern/ )
        {
            #print "$line";
            #printf "%19s %12d %10d %10d\n", $2,$1,$3,$4;

            # New timestamp
            $timestamp2remember = $2;
            next if ($timestamp2remember le $old_timestamp);

            # Insert search results into Oracle table. Autocommit is in effect.
            eval
            {
                $sth->bind_param(1, $2);
                $sth->bind_param(2, $1);
                $sth->bind_param(3, $3);
                $sth->bind_param(4, $4);
                $sth->execute();
            };
            if ( $@ )
            {
                warn "Database error: $DBI::errstr\n";
                $dbh->rollback(); #just die if rollback is failing
            }
        }
    }
}
