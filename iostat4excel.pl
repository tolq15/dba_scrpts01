#!/usr/bin/perl -w

#--------------------------------------------------------------------
# r/s      - The number of read  requests that were issued to the device per second.
# w/s      - The number of write requests that were issued to the device per second.
# rkB/s    - The number of kilobytes read   from the device per second.
# wkB/s    - The number of kilobytes written  to the device per second.
# avgqu-sz - The average queue length of the requests that were issued
#            to the device.
# await    - The average time (in  milliseconds) for I/O requests issued
#            to the device to be served. This includes the time spent by
#            the requests in queue and the time  spent servicing them.
# svctm    - The  average service time (in milliseconds) for I/O requests that
#            were issued to the device.
# utilpc   - Percentage of CPU time during which I/O requests were issued to
#            the device (bandwidth utilization for the device).
#            Device saturation occurs when this value is close to 100%.

# Hash %fs_name was created based on output from next two commands (run as root)
# at 09/17/2013
# $> /sbin/multipath -l
# $> /sbin/lvm pvscan

# RESULT:
# -------
# sdi+   =>                 oracle0
# sdj+   =>                 oracle1
# sdk+   =>                 oracle2
# sdl+   =>                 oracle3
# dm-14- => sdq- => sdr- => oracle4
# dm-11  => sde  => sdm+ => oracle5
# dm-12  => sdn+ => sdf  => oracle6
# dm-13  => sdg  => sdo+ => oracle7
# dm-10  => sdp+ => sdh  => oracle8
# dm-16+ => sds+ =>      => oracle9

# In case of multipath (+) indicate current path, (-) indicate no-current path.

#----------------------------------------------------------------------
use strict;
use warnings;
use English;
use FileHandle;
use Getopt::Long;
use File::Basename;
use Excel::Writer::XLSX;
use Mail::Sender;
use Data::Dumper;

# Read files from directory
# /home/oracle/tolq/oswbb/archive/oswiostat/
# files like
# STPHORACLEDB04_iostat_13.08.28.2100.dat
# ...
# STPHORACLEDB04_iostat_13.09.06.1500.dat
#

# To convert month name to month number
my $mon_num;
my %month = ( JAN=>'01', FEB=>'02', MAR=>'03',
              APR=>'04', MAY=>'05', JUN=>'06',
              JUL=>'07', AUG=>'08', SEP=>'09',
              OCT=>'10', NOV=>'11', DEC=>'12' );
my %fs_name = (sdi=>'oracle0',
               sdj=>'oracle1',
               sdk=>'oracle2',
               sdl=>'oracle3',
               sdm=>'oracle5',
               sdn=>'oracle6',
               sdo=>'oracle7',
               sdp=>'oracle8',
               sds=>'oracle9',
           );

#------------------------------#
# To store data for all charts #
#------------------------------#
my @data0X; # X axes (calendare date)

my $location    = $ENV{GE0_LOCATION};
my $server_name = $ENV{ORACLE_HOST_NAME};

my %chart_data; # key is the device_name points to data array for the CPU
my $ii = -1;    # to count spreadsheet rows

# To add timestamp to file name
my ($mday,$mon,$year) = (localtime)[3..5];
my $ymd = sprintf("%04d%02d%02d",$year+1900,$mon+1,$mday);

#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
# HARD-CODED                           #
# This should be placed in config file #
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
my $iostat_dir = '/home/oracle/tolq/oswbb/archive/oswiostat/';
my $work_dir   = '/home/oracle/scripts/Excel/';
my $file_name  = $work_dir
    . 'iostat_'
    . $location
    . '_'
    . $server_name
    . '_'
    . $ymd
    . '.xlsx';

# For each file in iostat directory
foreach my $data_file (glob("$iostat_dir/*.dat"))
#foreach my $data_file (glob("$iostat_dir/*.dat"))
{
    open my $file_handler, "<", $data_file
        or die "Can't read open '$data_file': $OS_ERROR";

    # For each line in the file
    while (<$file_handler>)
    {
        my $the_string = $_;

        # Find timestamp
        if ($the_string =~ /^zzz \*\*\*.+ (\w+) (\d+) (\S+) UTC (\d+)/)
        {
            # Convert timestamp from format
            # zzz ***Fri Aug 30 18:14:49 UTC 2013
            # to format yyyy.mm.dd.hh24:mi:ss
            my ($yyyy,$mm,$dd,$the_time) = ($4, $1, $2, $3);
            map {s/^(\w{3})/$month{uc $1}/;$mon_num = $_;} $mm; # !!!???

            $ii++; # set new value and use it for all other arrays
            $data0X[$ii] = $4.'.'.$mon_num.'.'.$2.'.'.$3;
            #print "$data0X[$ii]\n";
        }
        elsif ($the_string =~ /^(sd[ijklnmops])\s+\d+\.\d+\s+\d+\.\d+\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+\d+\.\d+\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)/)
        {
            my $fs = $fs_name{$1};
            # Insert new row into two-dimentional data array
            @{$chart_data{$fs}[$ii]} = ( $2, $3, $4, $5, $6, $7, $8, $9 );
        }
    }   # while (<$file_handler>)

    close $file_handler or die "Can't read close '$data_file': $OS_ERROR";
}   # foreach my $data_file (glob("$iostat_dir/*.28.2200.dat"))

my $row_num = $ii + 1;
print "Row number: $row_num\n";

#print Dumper \%chart_data;

#exit;

# Spreadsheet column headers
# 'Stat Value' can be %user, %sys, ....
my $headings = [ 'Date (yyyy.mm.dd.hh24:mi:ss)',
                 'r/s',
                 'w/s',
                 'rkB/s',
                 'wkB/s',
                 'avgqu-sz',
                 'await',
                 'savctm',
                 'utilpc',
            ];

#----------------------------#
# Prepare data for the chart #
#----------------------------#
my $workbook  = Excel::Writer::XLSX->new( $file_name );
my $bold      = $workbook->add_format( bold => 1 );
my $worksheet;

#-----------------------------------------#
# for each CPU create all possible charts #
#-----------------------------------------#
for my $the_dev (sort keys %chart_data)
{
    $worksheet = $workbook->add_worksheet($the_dev);

    # Region for data output
    $worksheet->write( 'A1', $headings, $bold );
    $worksheet->write( 'A2', [ \@data0X, $chart_data{$the_dev} ]);

    #======================#
    # Create a first chart #
    #======================#
    my $the_chart = $workbook->add_chart
    (
        type     => 'line',
        embedded => 1,
    );

    # Configure the series.
    $the_chart->add_series
    (
         name       => 'read requests per second.',
         categories => [ $the_dev, 1, $row_num, 0, 0 ],
         values     => [ $the_dev, 1, $row_num, 1, 1 ],
    );

    #Add a chart title and some axis labels.
    $the_chart->set_title ( name => "Number of read requests/sec for FS $the_dev in $location server $server_name" );
    $the_chart->set_x_axis( name => "Monitoring Time" );
    $the_chart->set_y_axis( name => "Read Requests/second" );
    $the_chart->set_legend( position => 'bottom' );

    # Insert the chart into the worksheet (with an offset).
    $worksheet->insert_chart( 'K3', $the_chart, 0, 0, 2.0, 1.5 );

    #=======================#
    # Create a second chart #
    #=======================#
    $the_chart = $workbook->add_chart
    (
        type     => 'line',
        embedded => 1,
     );

    # Configure the first series.
    $the_chart->add_series
    (
         name       => 'write requests per second',
         categories => [ $the_dev, 1, $row_num, 0, 0 ],
         values     => [ $the_dev, 1, $row_num, 2, 2 ],
    );

    #Add a chart title and some axis labels.
    $the_chart->set_title ( name => "Number of Write Requests/sec for FS $the_dev in $location server $server_name" );
    $the_chart->set_x_axis( name => "Monitoring Time" );
    $the_chart->set_y_axis( name => "Requests per second");
    $the_chart->set_legend( position => 'bottom' );

    # Insert the chart into the worksheet (with an offset).
    $worksheet->insert_chart( 'K30', $the_chart, 0, 0, 2.0, 1.5 );

    #======================#
    # Create a third chart #
    #======================#
    $the_chart = $workbook->add_chart
    (
        type     => 'line',
        embedded => 1,
     );

    # Configure the first series.
    $the_chart->add_series
    (
         name       => 'service time (msec)',
         categories => [ $the_dev, 1, $row_num, 0, 0 ],
         values     => [ $the_dev, 1, $row_num, 6, 6 ],
    );

    #Add a chart title and some axis labels.
    $the_chart->set_title ( name => "The average time (msec) for I/O requests to be served for FS $the_dev in $location server $server_name" );
    $the_chart->set_x_axis( name => "Monitoring Time" );
    $the_chart->set_y_axis( name => "Time in milliseconds");
    $the_chart->set_y_axis( max  => 50);
    $the_chart->set_legend( position => 'bottom' );

    # Insert the chart into the worksheet (with an offset).
    $worksheet->insert_chart( 'K55', $the_chart, 0, 0, 2.0, 1.5 );

}   # for my $the_dev (sort keys %chart_data)

# Excel Spreadsheet must be closed before attach to e-mail
$workbook->close();

exit;


