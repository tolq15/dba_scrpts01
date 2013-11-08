#!/usr/bin/perl -w

use strict;
use warnings;

# HARD-CODED file name
my $history = "/home/oracle/scripts/log/server_load_average_hist.log";

chomp (my $the_host = `hostname`);

# Parth uptime string
# 18:31:27 up 28 days, 20:27,  9 users,  load average: 0.37, 0.42, 0.48
my @load_average = map {/^\s+([0-9]+:[0-9]+:[0-9]+)\s.+load average: ([0-9]+\.[0-9]+), ([0-9]+\.[0-9]+), ([0-9]+\.[0-9]+)$/} `uptime`;

# Checke threshold (first argument) and send e-mail if needed
if (($load_average[1] > $ARGV[0]) || ($load_average[2] > $ARGV[0]) || ($load_average[3] > $ARGV[0]))
{
    `echo "$the_host: Average load is too high: $load_average[1], $load_average[2], $load_average[3]." | mailx -s "$the_host: Average load is too high." opsDBAdmin\@mobile.asp.nuance.com`;
}
else
{
    # Write to log file
    print "Load is OK: $load_average[1], $load_average[2], $load_average[3]\n";
}

# Write history file
open(HISTORY, ">> $history")
    or die "Cannot write to $history: $!";

print HISTORY "$load_average[0]: $load_average[1], $load_average[2], $load_average[3]\n";

exit;
