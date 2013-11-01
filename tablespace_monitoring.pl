#!/usr/bin/perl -w

#=================#
# All space in MB #
#=================#

use strict;
use warnings;
use DBI;
use FileHandle;
use DBD::Oracle qw(:ora_session_modes);
use Getopt::Long;
use File::Basename;
use Config::IniFiles;

# HARD-CODED PATH
use lib "/home/oracle/scripts";
require 'my_library.pl';

my @ts_drive_data;
my %ts_data;
my $mail_body;
my $pct_free = 0;

#------------------------#
# Parse input parameters #
#------------------------#
my $db_name;
my $percent_max;
GetOptions('dbname=s' => \$db_name, 'pct=i' => \$percent_max);
die "ERROR: Database name required\n" if (!defined $db_name);
die "ERROR: Maximum Percent Used is required\n" if (!defined $percent_max);

$db_name = uc $db_name;
chomp (my $the_host = `hostname`);

# Connect to the database
my $dbh = Connect2Oracle ($db_name);

#--------------------------------------------------------------------#
# Check the database role. This scripts can run on Primary database. #
# Views like dba_data_files, dba_tablespaces are not available on    #
# mounted database (Standby).                                        #
#--------------------------------------------------------------------#
my $sql01 = qq {select DATABASE_ROLE from v\$database};

my @tmp_row  = $dbh->selectrow_array($sql01);
if ($DBI::err)
{
    print "Fetch failed for $sql01 $DBI::errstr\n";
    $dbh->disconnect;
    exit 1;
}

my $current_db_role = $tmp_row[0];
die "$db_name role is not PRIMARY" if ($current_db_role ne 'PRIMARY');

#--------------------------------------#
# Find free space for each file system #
#--------------------------------------#
my @df_info = map {/^\/dev.+\s+\d+\s+\d+\s+(\d+)\s+\d+%\s+(\/\w*)$/} `df -hPm`;

my %filesystem_info;
my $ii = 0;

for ($ii=0; $ii < ($#df_info+1)/2; $ii++)
{
    $filesystem_info{$df_info[2*$ii+1]} = $df_info[2*$ii];
}

#-----------------------------------------------------------------------#
# For each tablespace find list of files with free/autoextensible space #
#-----------------------------------------------------------------------#
$sql01 = qq
{
select b.tablespace_name ts, b.file_name, b.bytes/1024/1024  alloc,
(select nvl(sum(a.bytes)/1024/1024,0)
   from dba_free_space  a
  where a.file_id(+) = b.file_id
    and a.tablespace_name = b.tablespace_name
) free,
decode(b.autoextensible, \'YES\', b.maxbytes - b.bytes, 0)/1024/1024 ext
from dba_data_files  b,dba_tablespaces c
where b.tablespace_name = c.tablespace_name
AND c.contents != \'TEMPORARY\'
AND c.contents != \'UNDO\'
order by 1, 2
};

my $result_array_ref  = $dbh->selectall_arrayref($sql01);
if ($DBI::err)
{
    print "Fetch failed for $sql01 $DBI::errstr\n";
    $dbh->disconnect;
    exit 1;
}

$sql01 = qq
{
select b.tablespace_name ts
      ,sum(b.bytes)/1024/1024  alloc
  from dba_data_files  b
      ,dba_tablespaces c
 where b.tablespace_name = c.tablespace_name
   AND c.contents != \'TEMPORARY\'
   AND c.contents != \'UNDO\'
 group by b.tablespace_name
 order by 1, 2
};

my $hash_ref = $dbh->selectall_hashref($sql01, 'TS');
if ($DBI::err)
{
    print "Fetch failed for $sql01 $DBI::errstr\n";
    $dbh->disconnect;
    exit 1;
}

my %ts_info;
for my $id (keys %$hash_ref)
{
    $ts_info{$id} = $hash_ref->{$id}->{ALLOC};
}

#------------------------------------#
# Find file system for each datafile #
#------------------------------------#
my $current_index = $#{$result_array_ref->[0]};

$ii = 0;
for (@$result_array_ref)
{
    # Find full directory name
    my $dirname = dirname($result_array_ref->[$ii][1]);

    # Add filesystem name and free space to the row
    if (`df -P $dirname` =~ m/^\/dev.+%\s+(\/\w*)$/m)
    {
        $result_array_ref->[$ii][$current_index+1] = $1;
        $result_array_ref->[$ii][$current_index+2] = $filesystem_info{$1};
    }
    else
    {
        # Something is wrong
        print "Xpen-to, ne pabotaet.\n";
    }

    $ii++;
}

#-----------------------#
# Create summary report #
#-----------------------#
print "                    Tablespace Allocatd(MB)   Free(MB) Extend(MB) % Used\n";
print "------------------------------ ------------   -------- ---------- ------\n";

# For each tablespace
for my $tablespace_name (keys %ts_info)
{
    my $ts_ext_sum  = 0;
    my $ts_free_sum = 0;
    my $tablespace_mb_allocated = $ts_info{$tablespace_name};

    # For each filesystem
    for my $filesystem_name (keys %filesystem_info)
    {
        my $filesystem_mb_free = $filesystem_info{$filesystem_name};

        # For each datafile
        $ii = 0;
        my $ts_fs_ext_sum  = 0;
        my $ts_fs_free_sum = 0;
        for (@$result_array_ref)
        {
            if (($result_array_ref->[$ii][0] eq $tablespace_name) &&
                ($result_array_ref->[$ii][5] eq $filesystem_name))
            {
                $ts_fs_ext_sum  += $result_array_ref->[$ii][4];
                $ts_fs_free_sum += $result_array_ref->[$ii][3];
            }
            $ii++;
        }

        $ts_ext_sum += $ts_fs_ext_sum > $filesystem_mb_free ?
            $filesystem_mb_free : $ts_fs_ext_sum;
        $ts_free_sum += $ts_fs_free_sum;
    }

    my $percent_used = int (($tablespace_mb_allocated - $ts_free_sum)*100/
                            ($tablespace_mb_allocated + $ts_ext_sum));

    printf "%30s %12.2f %10.2f %10.2f %6.2f\n", $tablespace_name, $tablespace_mb_allocated, $ts_free_sum, $ts_ext_sum, $percent_used;

    if ($percent_used >= $percent_max)
    {
        `echo "Server $the_host; Database: $db_name: Tablespace $tablespace_name have $percent_used% space used." | mailx -s "Server $the_host; Database: $db_name: Tablespace $tablespace_name have $percent_used% space used." opsDBAdmin\@mobile.asp.nuance.com`;
    }
}

exit;
