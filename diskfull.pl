#!/usr/bin/perl -w

use strict;
use warnings;

chomp (my $the_host = `hostname`);

print "Host Name: $the_host\n";

# Prepare info for devices "/dev..." using 'df' output
my @df_info = map {/^\/dev.+\s+(\d+)%\s+(\/\w*)$/} `df -hP`;

for (my $ii=0; $ii < ($#df_info+1)/2; $ii++)
{
    if ($df_info[$ii*2] >= $ARGV[0])
    {
        `echo "$the_host : $df_info[$ii*2+1] $df_info[$ii*2]% space used." | mailx -s "$the_host : $df_info[$ii*2+1] $df_info[$ii*2]% space used." opsDBAdmin\@mobile.asp.nuance.com`;
    }
    print "FS: $df_info[$ii*2+1] \t=> $df_info[$ii*2]% full.\n";
}

exit;
