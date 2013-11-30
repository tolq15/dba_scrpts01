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
use File::Basename;
use Mail::Sender;

use lib $ENV{WORKING_DIR};
require $ENV{MY_LIBRARY};

my $db_name     = uc $ENV{ORACLE_SID};
my $server_name = uc $ENV{ORACLE_HOST_NAME};
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
my $message  = "Database $db_name on server $server_name.\nFast Failover Status: $status\nObserver: $observer";

if (($observer ne 'YES') or ($status ne 'TARGET UNDER LAG LIMIT'))
{
    my $subject = "Warning from Fast Failover Observer on $server_name.";
    SendAlert ( $server_name, $db_name, $subject, $message );
}
else
{
    print "$message\n";
}

exit;
