#!/usr/bin/perl -w

#============================================#
# Generate charts based on data collected by #
# script parse_gg_stats.pl.                  #
#============================================#
#================================================================#
# This script should be run from directory /home/oracle/scripts. #
# Charts will be created in directory /home/oracle/scripts/log.  #
#                                                                #
# Run command (one line):                                        #
# perl -I/home/oracle/tolq/ChartDirector/lib/                    #
# gg_stats_pic.pl -sid nvcsom1 -days 2 -dc Somerville            #
#================================================================#

use strict;
use DBI;
use FileHandle;
use DBD::Oracle qw(:ora_session_modes);
use Getopt::Long;
use File::Basename;
use Config::IniFiles;
use perlchartdir;
use Mail::Sender;

use lib $ENV{WORKING_DIR};
require $ENV{MY_LIBRARY};

#------------------------#
# Parse input parameters #
#------------------------#
my $db_name = uc $ENV{ORACLE_SID};
chomp (my $server_name = `hostname`);
my $jj = 0;
my $days;
my $location;

GetOptions('days:s', \$days, 'dc:s', \$location);
die "ERROR: Number of days required\n" if (!defined $days);
die "ERROR: DC location required\n"    if (!defined $location);

my @attached_files;

# Connect to the database
my $dbh = Connect2Oracle ($db_name);

#
# Check for PRIMARY
#
my $sql01 = qq
{
SELECT sys_context('USERENV', 'DATABASE_ROLE') the_role FROM dual
};

my @db_role  = $dbh->selectrow_array($sql01);
if ($DBI::err)
{
    print "Fetch failed for $sql01 $DBI::errstr\n";
    $dbh->disconnect;
    exit 1;
}

if ($db_role[0] ne 'PRIMARY')
{
    print "Database role is not PRIMARY. Do nothing.\n";
    exit;
}

#--------------------------------#
# Get list of replicat processes #
#--------------------------------#
$sql01 = qq
{
select unique replicat_name from dba_monitor.gg_replicat_stats order by 1
};

my $result_array_ref  = $dbh->selectall_arrayref($sql01);
if ($DBI::err)
{
    print "Fetch failed for $sql01 $DBI::errstr\n";
    $dbh->disconnect;
    exit 1;
}

#=========================#
# Generate all chart data #
#=========================#
for my $ref (@$result_array_ref)
{
    my $replicat_name = $ref->[0];

    my $file_name;
    
    #----------------------------#
    # Select data for the chart. #
    #----------------------------#
    $sql01 = qq
{
select to_char(run_date,'yyyy mm dd hh24 mi ss')
      ,inserts - lag(inserts,1) over (partition by stats_since order by run_date)
      ,deletes - lag(deletes,1) over (partition by stats_since order by run_date)
      ,updates - lag(updates,1) over (partition by stats_since order by run_date)
  from dba_monitor.gg_replicat_stats
 where replicat_name = '$replicat_name'
   and stats_name    = 'Total'
   and run_date      > sysdate - $days
 order by run_date
};

    my $result_arrayref  = $dbh->selectall_arrayref($sql01);
    if ($DBI::err)
    {
        print "Fetch failed for $sql01 $DBI::errstr\n";
        $dbh->disconnect;
        exit 1;
    }

    #------------------------#
    # Prepare data for chart #
    #------------------------#
    my @data0X; # X axes (array of labels)
    my @data1Y; # Y value for inserts
    my @data2Y; # Y value for deletes
    my @data3Y; # Y value for updates

    #
    # Populate three attays with query resultes.
    # Batch job runs each 15 minutes. Select statement returns
    # number of transactions (insert/delete/update) in last 15 minuts.
    # We create chart for number of transaction per minute.
    #
    my $ii = 0;
    for my $ref (@$result_arrayref)
    {
        $data0X[$ii] = $ref->[0];
        $data1Y[$ii] = defined $ref->[1] ? $ref->[1]/15 : 0;
        $data2Y[$ii] = defined $ref->[2] ? $ref->[2]/15 : 0;
        $data3Y[$ii] = defined $ref->[3] ? $ref->[3]/15 : 0;
        $ii++;
    }

    #-----------------------------------------------------#
    # Convert 'days' format from Oracle scring to         #
    # three numbers, required for perlchartdir::chartTime #
    #-----------------------------------------------------#
    for (my $yy = 0; $yy <= $#data0X; $yy++)
    {
        my ($year,$month,$day,$hour,$minute,$second) = split (/ /, $data0X[$yy]);

        # To remove liding zeros.
        $month  += 0;
        $day    += 0;
        $hour   += 0;
        $minute += 0;
        $second += 0;

        $data0X[$yy] = perlchartdir::chartTime($year,$month,$day,$hour,$minute,$second);
        #    print "Date: $year,$month,$day; Used: $data1Y[$yy]; Allocated: $data2Y[$yy]\n";
        #    print "Date: $data0X[$yy]; Used: $data1Y[$yy]; Allocated: $data2Y[$yy]\n";
    }

    #------------------#
    # Create the chart #
    #------------------#

    # Create a XYChart object of size 1100 x 600 pixels.
#    my $c = new XYChart(1100, 600);
    my $c = new XYChart(1100, 600, 0xffffc0, 0x000000);

    # Set the plotarea at (100, 100) and of size 900 x 400 pixels.
#    $c->setPlotArea(100, 100, 900, 400,
#                    $c->linearGradientColor(0, 55, 0, 335, 0x888888, 0x000000), -1, 0xffffff, 0xffffff);
    $c->setPlotArea(100, 100, 900, 400)->setBackground(0xffffff);

    # Add a legend box at (100, 50)
    $c->addLegend(100, 50, 0, "arialbd.ttf", 8)->setBackground($perlchartdir::Transparent);

    # Add a title box to the chart
    $c->addTitle("Data from GoldenGate for Replicat $replicat_name\nDatabase: $db_name in $location in Last $days Days"
                 ,"arialbd.ttf", 14);

    # Set x-axis tick density to 30 pixels and y-axis tick density to 30 pixels.
    # ChartDirector auto-scaling will use this as the guidelines when putting ticks on
    # the x-axis and y-axis.
    $c->yAxis()->setTickDensity(30);
    $c->xAxis()->setTickDensity(30);
    $c->xAxis()->setLabelStep(40);   # skip each 5-th lable

    # Set axis label style to 8pts Arial Bold
    $c->xAxis()->setLabelStyle ("arialbd.ttf", 8);
    $c->yAxis()->setLabelStyle ("arialbd.ttf", 8);

    # Add axis title using 10pts Arial Bold font
    $c->yAxis()->setTitle("Number of Transactions Per Minute" ,"arialbd.ttf", 12);
    $c->xAxis()->setTitle("Last $days Days"                   ,"arialbd.ttf", 12);

    # Set the axes line width to 3 pixels
    $c->xAxis()->setWidth(3);
    $c->yAxis()->setWidth(3);

    # Set the axis label format to ',' thousand separator
    $c->yAxis()->setLabelFormat("{value|,}");

    # Add the data series
    my $layer = $c->addLineLayer2();
    $layer->setXData(\@data0X);
    $layer->addDataSet(\@data1Y, 0x66aaee, "Number of Inserts");
    $layer->addDataSet(\@data2Y, 0xeebb22, "Number of Deletes");
    $layer->addDataSet(\@data3Y, 0x66bb22, "Number of Updates");
    $layer->setLineWidth(2);

    # Output the chart in picture directory
    $file_name = '/home/oracle/scripts/pictures/gg_stats_' . $db_name . '_' . $replicat_name . '.png';
    $c->makeChart($file_name);

    $attached_files[$jj] = $file_name;
    $jj++;
    print "Done: $file_name\n";
}

#
# Send e-mail with attached pictures
#            to      => 'opsDBAdmin@mobile.asp.nuance.com',
#            to      => 'anatoli.lyssak@nuance.com',
#? anatoli.lyssak@mobile.asp.nuance.com
my $sender=new Mail::Sender({
                             smtp => 'stoam02.ksea.net',
                             from => 'oracle@'.$server_name,
                           });

$sender->OpenMultipart({
                        to      => 'opsDBAdmin@mobile.asp.nuance.com',
                        subject => 'GoldenGate Replicat Processes in ' . $location,
                      });

$sender->Body();
$sender->SendLine('Find attached files with charts.');
$sender->Attach({ file => \@attached_files });
$sender->Close;

exit;

