#!/usr/bin/perl -w

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
# /home/oracle/tolq/oswbb/archive/oswmpstat/
# files like
# smphoracledb01.som.local_mpstat_13.08.29.0200.dat
# ...
# smphoracledb01.som.local_mpstat_13.08.30.1900.dat
#

# To convert month name to month number
my $mon_num;
my %month = ( JAN=>'01', FEB=>'02', MAR=>'03',
              APR=>'04', MAY=>'05', JUN=>'06',
              JUL=>'07', AUG=>'08', SEP=>'09',
              OCT=>'10', NOV=>'11', DEC=>'12' );

#------------------------------#
# To store data for all charts #
#------------------------------#
my @data0X; # X axes (calendare date)

my $location    = $ENV{GE0_LOCATION};
my $server_name = $ENV{ORACLE_HOST_NAME};

my %chart_data; # key is the CPU# points to data array for the CPU
my $ii = -1;    # to count spreadsheet rows

# To add timestamp to file name
my ($mday,$mon,$year) = (localtime)[3..5];
my $ymd = sprintf("%04d%02d%02d",$year+1900,$mon+1,$mday);

#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
# HARD-CODED                           #
# This should be placed in config file #
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!#
my $mpstat_dir = '/home/oracle/tolq/oswbb/archive/oswmpstat/';
my $work_dir   = '/home/oracle/scripts/Excel/';
my $file_name  = $work_dir
    . 'mpstat_'
    . $location
    . '_'
    . $server_name
    . '_'
    . $ymd
    . '.xlsx';

# For each file in mpstat directory
#foreach my $data_file (glob("$mpstat_dir/*.28.*.dat"))
#foreach my $data_file (glob("$mpstat_dir/*.28.2200.dat"))
foreach my $data_file (glob("$mpstat_dir/*.dat"))
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
        }
        elsif ($the_string =~ /^Average:\s+(\d+)\s+(\d+\.\d+)\s+\d+\.\d+\s+(\d+\.\d+)\s+(\d+\.\d+)\s+\d+\.\d+\s+\d+\.\d+\s+\d+\.\d+\s+(\d+\.\d+)/)
        {
            # Extract only lines like 'Average:     <CPU#>'
            # Fill in data array
            # Average: CPU %user %nice %sys %iowait %irq %soft %steal %idle i
            # Average:  11  0.44  0.00 0.00    2.67 0.00  0.89   0.00 96.00 0
            # Extract values: CPU, %user, %sys, %iowait, %idle
            # Insert new row into two-dimentional data array
            @{$chart_data{$1}[$ii]} = ( $2, $3, $4, $5 );
        }

    }   # while (<$file_handler>)

    close $file_handler or die "Can't read close '$data_file': $OS_ERROR";
}   # foreach my $data_file (glob("$mpstat_dir/*.28.2200.dat"))

my $row_num = $ii + 1;
print "Row number: $row_num\n";

#print Dumper \%chart_data;

#exit;

# Spreadsheet column headers
# 'Stat Value' can be %user, %sys, ....
my $headings = [ 'Date (yyyy.mm.dd.hh24:mi:ss)',
                 'user',
                 'sys',
                 'iowait',
                 'idle',
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
for my $the_cpu (sort keys %chart_data)
{
    my $worksheet_name = 'CPU'.$the_cpu;
    $worksheet = $workbook->add_worksheet('CPU'.$the_cpu);

    # Region for data output
    $worksheet->write( 'A1', $headings, $bold );
    $worksheet->write( 'A2', [ \@data0X, $chart_data{$the_cpu} ]);

    # Create a column stacked chart
    my $the_chart = $workbook->add_chart
    (
        type     => 'column',
        embedded => 1,
        subtype  => 'stacked'
     );

    # Configure the first series.
    $the_chart->add_series
    (
         name       => 'User Mode',
         categories => [ $worksheet_name, 1, $row_num, 0, 0 ],
         values     => [ $worksheet_name, 1, $row_num, 1, 1 ],
         gap        => 0,
    );

    # Configure the first series.
    $the_chart->add_series
    (
         name       => 'System Mode',
         categories => [ $worksheet_name, 1, $row_num, 0, 0 ],
         values     => [ $worksheet_name, 1, $row_num, 2, 2 ],
         gap        => 0,
    );

    # Configure the first series.
    $the_chart->add_series
    (
         name       => 'IO Wait',
         categories => [ $worksheet_name, 1, $row_num, 0, 0 ],
         values     => [ $worksheet_name, 1, $row_num, 3, 3 ],
         gap        => 0,
    );

    # Configure the first series.
    $the_chart->add_series
    (
         name       => 'Idle',
         categories => [ $worksheet_name, 1, $row_num, 0, 0 ],
         values     => [ $worksheet_name, 1, $row_num, 4, 4 ],
         gap        => 0,
    );

    # Add a chart title and some axis labels.
    $the_chart->set_title ( name => "Summary of CPU$the_cpu Usage in $location server $server_name" );
    $the_chart->set_x_axis( name => "Last Two Weeks" );
    $the_chart->set_y_axis( name => 'Pecents' );

    # Set an Excel chart style.
    #$the_chart->set_style( 13 );

    # Insert the chart into the worksheet (with an offset).
    $worksheet->insert_chart( 'F2', $the_chart, 0, 0, 2.0, 1.5 );


}   # for my $the_cpu (sort keys %chart_data)

# Excel Spreadsheet must be closed before attach to e-mail
$workbook->close();

exit;
