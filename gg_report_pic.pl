#!/usr/bin/perl -w

#============================================#
# Generate charts based on data collected by #
# script parse_gg_report.pl.                 #
#============================================#

use strict;
use DBI;
use FileHandle;
use DBD::Oracle qw(:ora_session_modes);
use Getopt::Long;
use File::Basename;
use Config::IniFiles;
use Mail::Sender;
use perlchartdir;

use lib $ENV{WORKING_DIR};
require $ENV{MY_LIBRARY};

#------------------------#
# Parse input parameters #
#------------------------#
my $db_name = uc $ENV{ORACLE_SID};
chomp (my $server_name = `hostname`);
my $days;
my $location;
my $jj = 0;

GetOptions('days:s', \$days, 'dc:s', \$location);
die "ERROR: Number of days required\n" if (!defined $days);
die "ERROR: DC location required\n"    if (!defined $location);

my @attached_files;

# Connect to the database
my $dbh = Connect2Oracle ($db_name);

#
# Check for PRIMARY
#
if ( CheckDBRole($db_name) !~ m/PRIMARY/ )
{
    print "CheckDBRole did not return PRIMARY\n";
    exit 1;
}

#--------------------#
# Get list of tables #
#--------------------#
my $sql01 = qq
{
select unique table_name from dba_monitor.gg_activity1
};

my $result_array_ref  = $dbh->selectall_arrayref($sql01);
if ($DBI::err)
{
    print "Fetch failed for $sql01 $DBI::errstr\n";
    $dbh->disconnect;
    exit 1;
}

#====================================#
# Generate chart for each table name #
#====================================#
for my $ref (@$result_array_ref)
{
    my $table_name = $ref->[0];

    my $file_name;
    
    #----------------------------#
    # Select data for the chart. #
    #----------------------------#
    $sql01 = qq
{
select to_char(report_date,'mm/dd')
      ,inserts - lag(inserts,1) over (partition by since_date order by report_date)
      ,deletes - lag(deletes,1) over (partition by since_date order by report_date)
      ,updates - lag(updates,1) over (partition by since_date order by report_date)
  from dba_monitor.gg_activity1
 where table_name = '$table_name'
   and report_date > sysdate-$days
 order by report_date
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
    # Populate three attays with query resultes
    #
    my $ii = 0;
    for my $ref (@$result_arrayref)
    {
        $data0X[$ii] = $ref->[0];
        $data1Y[$ii] = defined $ref->[1] ? $ref->[1] : 0;
        $data2Y[$ii] = defined $ref->[2] ? $ref->[2] : 0;
        $data3Y[$ii] = defined $ref->[3] ? $ref->[3] : 0;
        $ii++;
    }

    #------------------#
    # Create the chart #
    #------------------#

    # Create a XYChart object of size 1100 x 600 pixels.
    my $c = new XYChart(1100, 600);

    # Set the plotarea at (100, 100) and of size 900 x 400 pixels.
    $c->setPlotArea(100, 100, 900, 400,
                    $c->linearGradientColor(0, 55, 0, 335, 0x888888, 0x000000), -1, 0xffffff, 0xffffff);

    # Add a legend box at (100, 50)
    $c->addLegend(100, 50, 0, "arialbd.ttf", 8)->setBackground($perlchartdir::Transparent);

    # Set the x axis labels
    $c->xAxis()->setLabels(\@data0X);

    # Add a title box to the chart
    $c->addTitle("Data from GoldenGate PUMP_1 Report for Table $table_name \nin last $days days. Database: $db_name in $location."
                 ,"arialbd.ttf", 14);

    # Set x-axis tick density to 30 pixels and y-axis tick density to 30 pixels.
    # ChartDirector auto-scaling will use this as the guidelines when putting ticks on
    # the x-axis and y-axis.
    $c->yAxis()->setTickDensity(30);
    $c->xAxis()->setTickDensity(30);
    $c->xAxis()->setLabelStep(2);   # skip each 2-nd lable

    # Set axis label style to 8pts Arial Bold
    $c->xAxis()->setLabelStyle ("arialbd.ttf", 8);
    $c->yAxis()->setLabelStyle ("arialbd.ttf", 8);

    # Add axis title using 10pts Arial Bold font
    $c->yAxis()->setTitle("Number of Transactions" ,"arialbd.ttf", 12);
    $c->xAxis()->setTitle("Last $days Days"        ,"arialbd.ttf", 12);

    # Set the axes line width to 3 pixels
    $c->xAxis()->setWidth(2);
    $c->yAxis()->setWidth(2);

    # Set the axis label format to ',' thousand separator
    $c->yAxis()->setLabelFormat("{value|,}");

    my $layer = $c->addBarLayer2($perlchartdir::Side, 4);
    $layer->addDataSet(\@data1Y, 0x66aaee, "Number of Inserts");
    $layer->addDataSet(\@data2Y, 0xeebb22, "Number of Deletes");
    $layer->addDataSet(\@data3Y, 0x66bb22, "Number of Updates");

    # Configure the bars within a group to touch each others (no gap)
    $layer->setBarGap(0.2, $perlchartdir::TouchBar);

    # Output the chart in log directory
    $file_name = '/home/oracle/scripts/pictures/gg_report_' . $db_name . '_' . $table_name . '.png';
    $c->makeChart($file_name);

    $attached_files[$jj] = $file_name;
    $jj++;
    print "Done: $file_name\n";
}

#
# Send e-mail with attached pictures
#            to      => 'anatoli.lyssak@nuance.com',
#            to      => 'opsDBAdmin@mobile.asp.nuance.com',
my $sender=new Mail::Sender({
                             smtp => 'stoam02.ksea.net',
                             from => 'oracle@'.$server_name,
                           });

$sender->OpenMultipart({
                        to      => 'anatoli.lyssak@mobile.asp.nuance.com',
                        subject => 'NVC Application Activities in ' . $location,
                      });

$sender->Body();
$sender->SendLine('Find attached files with charts.');
$sender->Attach({ file => \@attached_files });
$sender->Close;

exit;

