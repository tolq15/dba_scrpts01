#!/usr/bin/perl -w

use strict;
use DBI;
use FileHandle;
use DBD::Oracle qw(:ora_session_modes);
use Getopt::Long;
use File::Basename;
use perlchartdir;

use lib $ENV{WORKING_DIR};
require $ENV{MY_LIBRARY};

#------------------------#
# Parse input parameters #
#------------------------#
my $db_name = uc $ENV{ORACLE_SID};
my $server_name;
my $ts_name;
my $days;

GetOptions('ts:s', \$ts_name, 'days:s', \$days);
die "ERROR: Tablespace name required\n" if (!defined $ts_name);
die "ERROR: Number of days required\n"  if (!defined $days);

my $location = 'Seattle';

#---------------------------------------------------#
# Prepare it this way in case of time gaps in data. #
# Other way is just set first and last day.         #
# Select data for last $days days.                  #
#---------------------------------------------------#
my $sql01 = qq
{
select to_char(the_date,'yyyy mm dd')
      ,USED_MB/1024
      ,ALLOCATED_MB/1024
  from dba_monitor.ts_mon
 where TABLESPACE_NAME='$ts_name'
   and the_date > (select max(the_date)-$days
                     from dba_monitor.ts_mon
                    where TABLESPACE_NAME='$ts_name')
 order by 1
};

#
# Connect to the database and run query
#
my $dbh = Connect2Oracle ($db_name);

my $result_array_ref  = $dbh->selectall_arrayref($sql01);
if ($DBI::err)
{
    print "Fetch failed for $sql01 $DBI::errstr\n";
    $dbh->disconnect;
    exit 1;
}

#---------------------------#
# Prepare data for TS chart #
#---------------------------#
my @data0X; # X axes (calendare date)
my @data1Y; # Y value for used space in GB
my @data2Y; # Y value for allocated space in Gb

#
# Populate three attays with query resultes
#
my $ii = 0;
for my $ref (@$result_array_ref)
{
    $data0X[$ii] = $ref->[0];
    $data1Y[$ii] = $ref->[1];
    $data2Y[$ii] = $ref->[2]-$ref->[1];
    $ii++;
}

#
# Convert 'days' format from Oracle scring to three numbers,
# required for perlchartdir::chartTime
#
for (my $yy = 0; $yy <= $#data0X; $yy++)
{
    my ($year,$month,$day) = split (/ /, $data0X[$yy]);

    # To remove liding zeros.
    $month += 0;
    $day   += 0;

    $data0X[$yy] = perlchartdir::chartTime($year,$month,$day);
#    print "Date: $year,$month,$day; Used: $data1Y[$yy]; Allocated: $data2Y[$yy]\n";
#    print "Date: $data0X[$yy]; Used: $data1Y[$yy]; Allocated: $data2Y[$yy]\n";
}

# Create a XYChart object of size 1100 x 600 pixels.
# Set the background to pale yellow (0xffffc0) with a black border (0x0)
my $c = new XYChart(1100, 600, 0xffffc0, 0x000000);

# Set the plotarea at (100, 100) and of size 900 x 400 pixels.
# Use white (0xffffff) background.
$c->setPlotArea(100, 100, 900, 400)->setBackground(0xffffff);

# Add a legend box at (50, 185) (below of plot area) using horizontal layout. Use 8
# pts Arial font with Transparent background.
$c->addLegend(100, 50, 0, "arialbd.ttf", 8)->setBackground($perlchartdir::Transparent);

# Add a title box to the chart using 8 pts Arial Bold font, with yellow (0xffff40)
# background and a black border (0x0)
$c->addTitle("Disk Space Usage (GB) in last $days days.\nTablespace: $ts_name; Database: $db_name in $location.", "arialbd.ttf", 14)->setBackground(0xffff40, 0);

# Set x-axis tick density to 30 pixels and y-axis tick density to 30 pixels.
# ChartDirector auto-scaling will use this as the guidelines when putting ticks on
# the x-axis and y-axis.
$c->yAxis()->setTickDensity(30);
$c->xAxis()->setTickDensity(30);

# Set axis label style to 8pts Arial Bold
$c->xAxis()->setLabelStyle ("arialbd.ttf", 8);
$c->yAxis()->setLabelStyle ("arialbd.ttf", 8);

# Add axis title using 10pts Arial Bold font
$c->yAxis()->setTitle("Disk Space in GB", "arialbd.ttf", 12);
$c->xAxis()->setTitle("Last $days days",  "arialbd.ttf", 12);

# Set the axes line width to 3 pixels
$c->xAxis()->setWidth(3);
$c->yAxis()->setWidth(3);

# Add an stack area layer with two data sets
my $layer = $c->addAreaLayer2($perlchartdir::Stack);
$layer->addDataSet(\@data1Y, 0x4040ff, "Used GB");
$layer->addDataSet(\@data2Y, 0xff4040, "Allocated GB");
$layer->setXData(  \@data0X);

# Output the chart in log directory
$c->makeChart('./pictures/' . $db_name . '_' . $ts_name . '_space.png');

print "Done $ts_name\n";

exit;
