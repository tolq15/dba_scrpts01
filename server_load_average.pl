#!/usr/bin/perl -w

use strict;
use warnings;
use Mail::Sender;

use lib $ENV{WORKING_DIR};
require $ENV{MY_LIBRARY};

my $history     = $ENV{WORKING_DIR} . "/log/server_load_average_hist.log";
my $server_name = $ENV{ORACLE_HOST_NAME};

# Parse uptime string
# 18:31:27 up 28 days, 20:27,  9 users,  load average: 0.37, 0.42, 0.48
my @load_average = map {/.+\s+load average: ([0-9]+\.[0-9]+), ([0-9]+\.[0-9]+), ([0-9]+\.[0-9]+)$/} `uptime`;

# Checke threshold (first argument) and send e-mail if needed
if (   ($load_average[0] > $ARGV[0])
    || ($load_average[1] > $ARGV[0])
    || ($load_average[2] > $ARGV[0])
   )
{
    my $message = "$server_name: Average load is too high: $load_average[0], $load_average[1], $load_average[2] in $ENV{GE0_LOCATION}";
    my $subject = "Server Average Load is High for server $server_name in $ENV{GE0_LOCATION}";
    SendAlert ( $server_name, $subject, $message );
}
else
{
    # Write to log file
    print "Load is OK: $load_average[0], $load_average[1], $load_average[2]\n";
}

# Write history file
open(HISTORY, ">> $history")
    or die "Cannot write to $history: $!";

print HISTORY "$ENV{THE_TIME}: $load_average[0], $load_average[1], $load_average[2]\n";

exit;
