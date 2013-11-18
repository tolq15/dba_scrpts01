#!/usr/bin/perl -w

use strict;
use warnings;
use Config::IniFiles;
use Mail::Sender;

use lib $ENV{WORKING_DIR};
require $ENV{MY_LIBRARY};

my $db_name     = uc $ENV{ORACLE_SID};
my $server_name = uc $ENV{ORACLE_HOST_NAME};

print "Host Name: $server_name\n";

# Prepare info for devices "/dev..." using 'df' output
my @df_info = map {/^\/dev.+\s+(\d+)%\s+(\/\w*)$/} `df -hP`;

for (my $ii=0; $ii < ($#df_info+1)/2; $ii++)
{
    if ($df_info[$ii*2] >= $ARGV[0])
    {
        my $message = "$server_name : $df_info[$ii*2+1] $df_info[$ii*2]% space used.";
        SendAlert ( $server_name, $db_name, $message, $message);
    }
    print "FS: $df_info[$ii*2+1] \t=> $df_info[$ii*2]% full.\n";
}

exit;
