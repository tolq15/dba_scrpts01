#!/usr/bin/perl -w

###############################################
# Check status of Data Guard Observer using   #
# v$database.                                 #
###############################################

use strict;
use warnings;
use DBI;
use FileHandle;
use DBD::Oracle qw(:ora_session_modes);
use Getopt::Long;
use File::Basename;
use Config::IniFiles;

use lib $ENV{WORKING_DIR};
require $ENV{MY_LIBRARY};

my $db_name = uc $ENV{ORACLE_SID};
chomp (my $the_host = `hostname`);
my $mail_body;

my $dbh = Connect2Oracle ($db_name);

my $sql01 = qq
{
select FS_FAILOVER_STATUS, FS_FAILOVER_OBSERVER_PRESENT
  from v\$database
};

my $result_array_ref  = $dbh->selectall_arrayref($sql01);
if ($DBI::err)
{
    print "Fetch failed for $sql01 $DBI::errstr\n";
    $dbh->disconnect;
    exit 1;
}

my $status   = $result_array_ref->[0][0];
my $observer = $result_array_ref->[0][1];

if (($observer ne 'YES') or ($status ne 'TARGET UNDER LAG LIMIT'))
{
    `echo "Database $db_name on server $the_host.\nFast Failover Status: $status.\nObserver: $observer." | mailx -s "Warning from Fast Failover Observer on $the_host" opsDBAdmin\@mobile.asp.nuance.com`;
}

print "Database $db_name on server $the_host.\nFast Failover Status: $status.\nObserver: $observer.\n";

exit;
