#!/usr/bin/perl -w

#===========================================================#
# Script to parse GG output from 'send rep..., stats'
# 04/05/2013 Created
#
# Table was created as:
# create table dba_monitor.gg_replicat_stats
# (
#  run_date      date,
#  replicat_name varchar2(10),
#  table_name    varchar2(20),
#  stats_name    varchar2(10),
#  stats_since   date,
#  inserts       number,
#  updates       number,
#  deletes       number
# );
#
# Command line:
# STPHORACLEDB04:nvcsea3:/home/oracle/scripts
# > ./parse_gg_stats.pl -sid nvcsea3
#
#===========================================================#

use strict;
use Cwd;
use Getopt::Long;
use File::Basename;
use DBI;
use DBD::Oracle qw(:ora_session_modes);
use FileHandle;
use Time::Local;
use Config::IniFiles;

use lib $ENV{WORKING_DIR};
require $ENV{MY_LIBRARY};

my $report_directory = '/opt/oracle/product/gg';
my @pattern_str = ('^Start of Statistics at (.+)\.'
                   ,'^Replicating from SPEECH_OWNER.(\S+)'
                   ,'^\*\*\* (Total) statistics since (.+) \*\*\*$'
                   ,'Total inserts\s+([0-9]+)\.00'
                   ,'Total updates\s+([0-9]+)\.00'
                   ,'Total deletes\s+([0-9]+)\.00'
                   ,'^\*\*\* (Daily) statistics since (.+) \*\*\*$'
                   ,'Total inserts\s+([0-9]+)\.00'
                   ,'Total updates\s+([0-9]+)\.00'
                   ,'Total deletes\s+([0-9]+)\.00'
                   ,'^\*\*\* (Hourly) statistics since (.+) \*\*\*$'
                   ,'Total inserts\s+([0-9]+)\.00'
                   ,'Total updates\s+([0-9]+)\.00'
                   ,'Total deletes\s+([0-9]+)\.00'
               );
# It should be in .bash_profile_cron
# $ENV{ORACLE_HOME}     = '/opt/oracle/product/11.0/db_1';
# $ENV{LD_LIBRARY_PATH} = $ENV{ORACLE_HOME}.'/lib:/opt/oracle/product/gg';

my $array_size = $#pattern_str;

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
my $sql01 = qq{ INSERT INTO dba_monitor.gg_replicat_stats
( replicat_name,run_date,table_name,stats_name,stats_since,inserts,updates,deletes)
VALUES
( ?,to_date(?,'yyyy-mm-dd hh24:mi:ss'),?,?,to_date(?,'yyyy-mm-dd hh24:mi:ss'),?,?,?) };
my $sth = $dbh->prepare( $sql01 );

# Go to GG report directory
my $current_dir = getcwd;
chdir $report_directory;

#
# Get list of replicat processes
#
my @output = `echo info all | ./ggsci`;

# Parse GG output
my @replicate;
my $ii = 0;
for (@output)
{
    my $the_line = $_;
    #print "the line: $the_line";

    if ($the_line =~ /^REPLICAT\s+RUNNING\s+(\w+)\s+/)
    {
        $replicate[$ii++] = $1;
        #print "$the_line";
    }
}

#
# Run GG stats for each replicate and store in array
#
my @insert_values;
for (@replicate)
{
    my $rep_name = $_;
    my $jj = 0;

    #print "\n$rep_name\n";
    $insert_values[$jj++] = $rep_name;

    # Run GG command
    @output = `echo send $rep_name, stats | ./ggsci`;

    # Parse GG output
    $ii = 0;
    for (@output)
    {
        my $the_line = $_;
        #print "$the_line";
        #print "Search for: $pattern_str[$ii]\n";

        if ($the_line =~ /$pattern_str[$ii]/)
        {
            #print "$1  ";
            $insert_values[$jj++] = $1;
            if (defined $2)
            {
                 #print "$2";
                 $insert_values[$jj++] = $2;
            }
            if ($ii < $array_size){$ii++;} else {last;}
        }
    }

    #print "\n";
    #for (@insert_values)
    #{
    #    print "$_,\n";
    #}

    # Insert TOTAL
    eval
    {
        $sth->bind_param(1, $insert_values[0]);
        $sth->bind_param(2, $insert_values[1]);
        $sth->bind_param(3, $insert_values[2]);
        $sth->bind_param(4, $insert_values[3]);
        $sth->bind_param(5, $insert_values[4]);
        $sth->bind_param(6, $insert_values[5]);
        $sth->bind_param(7, $insert_values[6]);
        $sth->bind_param(8, $insert_values[7]);
        $sth->execute();
    };
    if ( $@ )
    {
        warn "Database error: $DBI::errstr\n";
        $dbh->rollback(); #just die if rollback is failing
    }
    # Insert DAILY
    eval
    {
        $sth->bind_param(1, $insert_values[0]);
        $sth->bind_param(2, $insert_values[1]);
        $sth->bind_param(3, $insert_values[2]);
        $sth->bind_param(4, $insert_values[8]);
        $sth->bind_param(5, $insert_values[9]);
        $sth->bind_param(6, $insert_values[10]);
        $sth->bind_param(7, $insert_values[11]);
        $sth->bind_param(8, $insert_values[12]);
        $sth->execute();
    };
    if ( $@ )
    {
        warn "Database error: $DBI::errstr\n";
        $dbh->rollback(); #just die if rollback is failing
    }
    # Insert HOURLY
    eval
    {
        $sth->bind_param(1, $insert_values[0]);
        $sth->bind_param(2, $insert_values[1]);
        $sth->bind_param(3, $insert_values[2]);
        $sth->bind_param(4, $insert_values[13]);
        $sth->bind_param(5, $insert_values[14]);
        $sth->bind_param(6, $insert_values[15]);
        $sth->bind_param(7, $insert_values[16]);
        $sth->bind_param(8, $insert_values[17]);
        $sth->execute();
    };
    if ( $@ )
    {
        warn "Database error: $DBI::errstr\n";
        $dbh->rollback(); #just die if rollback is failing
    }

    print "Done.\n";
}

exit;
