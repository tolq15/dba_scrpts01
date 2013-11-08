#!/usr/bin/perl -w

#================================================================#
# This script should be run from directory /home/oracle/scripts. #
# Charts will be created in directory /home/oracle/scripts/log.  #
#                                                                #
# Run command (one line):                                        #
# perl -I/home/oracle/tolq/ChartDirector/lib/                    #
# gg_report_records_pic.pl -sid nvcsom1 -days 2 -dc Somerville   #
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
my $days;
my $location;

GetOptions('days:s', \$days, 'dc:s', \$location);
die "ERROR: Number of days required\n" if (!defined $days);
die "ERROR: DC location required\n"    if (!defined $location);

# Names for different charts
my @title     = ("Total Number of Application Opereations (insert/delete/update) per Second in Last $days Days.\nDatabase: $db_name in $location. Source: GG PUMP process report."
                ,"Number of Contacts in Last $days Days.\nDatabase: $db_name in $location."
                ,"Number of Contacts per User in Last $days Days.\nDatabase: $db_name in $location.");
my @axis_y    = ("Operations in second"
                ,"Number of Contacts"
                ,"Number of Contacts per User");
my $name_pre  = '/home/oracle/scripts/pictures/' . $db_name;  # HARD-CODED !!!!
my @file_name = ($name_pre . "_app_operations.png");
#                ,$name_pre . "_contacts_rows.png"
#                ,$name_pre . "_contacts_per_user.png");

#---------------------------------------#
# Connect to the database and run query #
#---------------------------------------#
my $dbh = Connect2Oracle ($db_name);

#
# Check for primary
#
if ( CheckDBRole($db_name) !~ m/PRIMARY/ )
{
    print "CheckDBRole did not return PRIMARY\n";
    exit 1;
}

#---------------------------------------------------#
# Prepare it this way in case of time gaps in data. #
# Other way is just set first and last day.         #
# Select data for last $days days.                  #
#---------------------------------------------------#
my $sql01 = qq
{
select to_char(report_date,'yyyy mm dd hh24 mi ss')
      ,records
      ,rate
      ,delta
  from dba_monitor.gg_activity2
 where report_date > sysdate-$days
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
my @data1Y; # Y value for records
my @data2Y; # Y value for rate
my @data3Y; # Y value for delta

#
# Populate three with query resultes
#
my $ii = 0;
for my $ref (@$result_array_ref)
{
    $data0X[$ii] = $ref->[0];
    $data1Y[$ii] = $ref->[1];
    $data2Y[$ii] = $ref->[2];
    $data3Y[$ii] = $ref->[3];
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

#======================#
# Generate charts      #
#======================#
generate_the_chart($title[0], $axis_y[0], \@data3Y, $file_name[0]);
#generate_the_chart($title[1], $axis_y[1], \@data2Y, $file_name[1]);
#generate_the_chart($title[2], $axis_y[2], \@data3Y, $file_name[2]);

#
# Send e-mail if there are errors
#            to      => 'opsDBAdmin@mobile.asp.nuance.com',
#            to      => 'anatoli.lyssak@nuance.com',
# alias in Seattle:      anatoli.lyssak@mobile.asp.nuance.com
my $sender=new Mail::Sender({
                             smtp => 'stoam02.ksea.net',
                             from => 'oracle@'.$server_name,
                           });

$sender->OpenMultipart({
                        to      => 'anatoli.lyssak@mobile.asp.nuance.com',
                        subject => 'NVC Application Activities Records in ' . $location,
                      });

$sender->Body();
$sender->SendLine('Find attached files with charts.');
$sender->Attach({ file => \@file_name });
$sender->Close;

exit;


#xxxxxxxxxxxxxxxxxxxxxxxxxxx#
#     SUBROUTINS            #
#xxxxxxxxxxxxxxxxxxxxxxxxxxx#

sub generate_the_chart
{
    my ($the_title, $the_axis_y, $data_y, $file_name)  = @_;

    # Create a XYChart object of size 1100 x 600 pixels.
    # Set the background to pale yellow (0xffffc0) with a black border (0x0)
    my $c = new XYChart(1100, 600, 0xffffc0, 0x000000);

    # Set the plotarea at (100, 100) and of size 900 x 400 pixels.
    # Use white (0xffffff) background.
    $c->setPlotArea(100, 100, 900, 400)->setBackground(0xffffff);

    # Add a legend box at (50, 185) (below of plot area) using horizontal layout.
    # Use 8 pts Arial font with Transparent background.
    $c->addLegend(100, 50, 0, "arialbd.ttf", 8)->setBackground($perlchartdir::Transparent);

    # Add a title box to the chart using 8 pts Arial Bold font, with yellow (0xffff40)
    # background and a black border (0x0)
    $c->addTitle($the_title, "arialbd.ttf", 14)->setBackground(0xffff40, 0);

    # Set x-axis tick density to 30 pixels and y-axis tick density to 30 pixels.
    # ChartDirector auto-scaling will use this as the guidelines when putting ticks on
    # the x-axis and y-axis.
    $c->yAxis()->setTickDensity(30);
    $c->xAxis()->setTickDensity(30);
    $c->xAxis()->setLabelStep(40);   # skip lable

    # Set axis label style to 8pts Arial Bold
    $c->xAxis()->setLabelStyle ("arialbd.ttf", 8);
    $c->yAxis()->setLabelStyle ("arialbd.ttf", 8);

    # Add axis title using 10pts Arial Bold font
    $c->yAxis()->setTitle($the_axis_y, "arialbd.ttf", 12);
    $c->xAxis()->setTitle("Last $days days", "arialbd.ttf", 12);

    # Set the axes line width to 3 pixels
    $c->xAxis()->setWidth(3);
    $c->yAxis()->setWidth(3);

    # Set the axis label format to ',' thousand separator
    $c->yAxis()->setLabelFormat("{value|,}");

    # Add the first data series
    my $layer0 = $c->addLineLayer2();
    $layer0->addDataSet($data_y);
    $layer0->setXData(\@data0X);
    $layer0->setLineWidth(3);

    # Output the chart
    $c->makeChart($file_name);
    print "Chart $file_name is done.\n";
}

