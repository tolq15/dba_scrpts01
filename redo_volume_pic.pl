#!/usr/bin/perl -w

use strict;
use warnings;
use DBI;
use FileHandle;
use DBD::Oracle qw(:ora_session_modes);
use Getopt::Long;
use File::Basename;
use perlchartdir;

use lib $ENV{WORKING_DIR};
require $ENV{MY_LIBRARY};

my $db_name     = $ENV{ORACLE_SID};
my $server_name = $ENV{ORACLE_HOST_NAME};
my $location    = $ENV{GE0_LOCATION};

#------------------------#
# Parse input parameters #
#------------------------#
my $days;
GetOptions('days:s', \$days);
die "ERROR: Number of days required\n" if (!defined $days);

#
# Connect to the database and run query
#
my $dbh = Connect2Oracle ($db_name);

#
# Check for primary
#
if ( CheckDBRole($db_name) !~ m/PRIMARY/ )
{
    print "Database role is not PRIMARY. Exit.\n";
    exit 1;
}

#---------------------------------------------------#
# Prepare it this way in case of time gaps in data. #
# Other way is just set first and last day.         #
# Select data for last $days days.                  #
#---------------------------------------------------#
my $sql01 = qq
{
select to_char(the_day,'MON dd')
      ,redo_volume_gb
      ,logswitch
  from dba_monitor.day_redo_volume_gb
 where the_day > (select max(the_day)-$days from dba_monitor.day_redo_volume_gb)
 order by 1
};

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
my @data1Y; # Y value for logswitches
my @data2Y; # Y value for redo volume in Gb

#
# Populate three attays with query resultes
#
my $ii = 0;
for my $ref (@$result_array_ref)
{
    $data0X[$ii] = $ref->[0];
    $data1Y[$ii] = $ref->[1];
    $data2Y[$ii] = $ref->[2];
    $ii++;
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
$c->addTitle("Redo Log Volume (GB) in last $days days.\nDatabase: $db_name in $location.", "arialbd.ttf", 14)->setBackground(0xffff40, 0);

$c->xAxis()->setLabels(\@data0X);

# Set x-axis tick density to 30 pixels and y-axis tick density to 30 pixels.
# ChartDirector auto-scaling will use this as the guidelines when putting ticks on
# the x-axis and y-axis.
$c->xAxis()->setTickDensity(30);
$c->yAxis()->setTickDensity(30);
$c->yAxis2()->setTickDensity(30);

# Set axis label style to 8pts Arial Bold
$c->xAxis()->setLabelStyle ("arialbd.ttf", 8);
$c->yAxis()->setLabelStyle ("arialbd.ttf", 8);
$c->yAxis2()->setLabelStyle ("arialbd.ttf", 8);

# Add axis title using 10pts Arial Bold font
$c->xAxis()->setTitle("Last $days days"        ,"arialbd.ttf", 12);
$c->yAxis()->setTitle("Redo Volume in GB"      ,"arialbd.ttf", 12);
$c->yAxis2()->setTitle("Number of Logswitches" ,"arialbd.ttf", 12);

# Set the axes line width to 3 pixels
$c->xAxis()->setWidth(3);
$c->yAxis()->setWidth(3);
$c->yAxis2()->setWidth(3);

# Set the axis, label and title colors for the primary y axis to red (0xc00000) to
# match the first data set
$c->yAxis()->setColors( 0xc00000, 0xc00000, 0xc00000);
$c->yAxis2()->setColors(0x008000, 0x008000, 0x008000);

# Skip 4 lables
$c->xAxis()->setLabelStep(4);

# Add an stack area layer with two data sets
$c->addLineLayer(\@data1Y, 0xc00000)->setLineWidth(2);

my $layer = $c->addLineLayer(\@data2Y, 0x008000);
$layer->setLineWidth(2);
$layer->setUseYAxis2();

# Output the chart in log directory
$c->makeChart('./pictures/' . $db_name . '_redo_volume.png');

print "Done....\n";

exit;
