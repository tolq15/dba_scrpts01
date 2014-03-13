#!python
#==========================================================#
# Read memory stats from SAR files from /var/log/sa
# (default SAR log direstory)
# and generate Excel spreadsheet with the data and charts.
#
# Configuration file added
# [MEMORY]
# sar_dir=/var/log/sa
# output_dir=/home/oracle/scripts/Excel/
# column_headers=Date,Free Memory,Used Memore,Buffers,Cached,Free Swap,Used Swap,Swap Cad
#
# Crontab command (one line):
# 20 22 * * * . /home/oracle/scripts/.bash_profile_cron nvcsea3 nvcsea3b;
# python /home/oracle/scripts/sar_mem4excel.py > /home/oracle/scripts/log/sar_mem4excel.log 2>&1
#
#==========================================================#
import os
import ConfigParser
import re
import fileinput
import xlsxwriter

# Open config file and read parameters
# __file__ is a script name from command line.
# Example: ./script.py or /full/path/to/the/script.py
# os.path.splitext(__file__)[0] return __file__ without extention (.py);
# .split('/')[-1] return string after last '/'
script_name  = os.path.splitext(__file__)[0].split('/')[-1]
working_dir  = os.environ['WORKING_DIR']
config_param = ConfigParser.RawConfigParser()
config_param.read(working_dir + '/config/' + script_name + '.conf')

# Generate output file names
location   = os.environ['GE0_LOCATION']
hostname   = os.uname()[1]
excel_file = config_param.get('MEMORY', 'output_dir') + script_name + '_' + location + '_'+hostname + '_' + os.environ['THE_TIME'] + '.xlsx'
output_data_file = open(config_param.get('MEMORY', 'output_dir') + 'sar_mem4excel.csv', "w")

# Setup spreadsheet
file_timestamp = ''
worksheet_name = 'Memory Usage'
workbook       = xlsxwriter.Workbook(excel_file)
worksheet      = workbook.add_worksheet(worksheet_name)
bold           = workbook.add_format({'bold': 1})
column_headers = 0
row_number     = 0
start_reading  = 0

# Adjust the column width for date.
worksheet.set_column(0, 0, 20)

#-------------------------------------------#
# Read SAR log files in chronological order #
#-------------------------------------------#
# go to SAR directory
os.chdir(config_param.get('MEMORY', 'sar_dir'))

# List all files in this directory in chrono order
all_sar_files = sorted(filter(os.path.isfile, os.listdir('.')), key=os.path.getmtime)

# List only 'sar' files (text files)
text_files = [text_files for text_files in all_sar_files if re.match('^sar.*', text_files)]

#--------------------------------------------------------------#
# Read all memory stats data from SAR log files into one array #
#--------------------------------------------------------------#

# Looks at string
# 00:00:01    kbmemfree kbmemused  %memused kbbuffers  kbcached kbswpfree kbswpused  %swpused  kbswpcad
# and read untill string starting with 'Average'
for the_line in fileinput.input(text_files):
    # Read the first line of each file to find the date
    # Linux 2.6.32-431.el6.x86_64 (mtl-babardn06d.nuance.com)   2014-01-24 ...
    m_obj = re.match('Linux\s.*\s(\d{4}-\d\d-\d\d)$', the_line)
    if m_obj:
        file_timestamp =  m_obj.groups()[0]
        continue
    
    # Start record the data
    if re.match('.*\skbmemfree\s.*', the_line):
        # Set the flag
        start_reading = 1
        # Write header to spreadsheet and data file once only
        if column_headers == 0:
            worksheet.write_row('A1', config_param.get('MEMORY','column_headers').split(','), bold)
            output_data_file.write(config_param.get('MEMORY','column_headers_csv') + "\n")
            column_headers = 1
        continue
    
    # Stop record the data
    if re.match('^Average.*', the_line) and start_reading == 1:
        start_reading = 0
        continue

    # Record the data
    if start_reading == 1:
        # Skip all next headers
        if re.match('.*\skbmemfree\s.*', the_line):
            continue
        row_data = the_line.rstrip('\n').split()
        row_number += 1
        # Convert strings to numbers using float()
        # Keep only data required for charts
        # columns 0,1,2-(4+5),4,5
        the_data = ( file_timestamp+" "+row_data[0]            # date
                    ,round(( float(row_data[2])
                            -float(row_data[4])
                            -float(row_data[5]))/1024/1024,2)  # used
                    ,round(  float(row_data[4])/1024/1024,2)   # buffers
                    ,round(  float(row_data[5])/1024/1024,2)   # cached
                    ,round(  float(row_data[1])/1024/1024,2))  # free

        # Write to spreadsheet
        worksheet.write_row(row_number, 0, the_data)
        # Write to data file (in reverse order)
        output_data_file.write(file_timestamp + " " + row_data[0]                    + ","
                               +format(round(float(row_data[1])/1024/1024,2),"5.2f") + ","
                               +format(round(float(row_data[5])/1024/1024,2),"5.2f") + ","
                               +format(round(float(row_data[4])/1024/1024,2),"5.2f") + ","
                               +format(round(( float(row_data[2])
                                        -float(row_data[4])
                                        -float(row_data[5]))/1024/1024,2)   ,"5.2f") + "\n")
        
#---------------------#
# Excel data is ready #
# Generate chart      #
#---------------------#
print "Number of data rows: ",row_number

chart01 = workbook.add_chart({'type': 'area', 'subtype': 'stacked'})

# Configure the series.
# List is [ sheet_name, first_row, first_col, last_row, last_col ].
chart01.add_series({
    'name':       'Memory Used GB',
    'categories': [worksheet_name, 1, 0, row_number+1, 0],
    'values':     [worksheet_name, 1, 1, row_number+1, 1],
    })

chart01.add_series({
    'name':       'Buffers GB',
    'categories': [worksheet_name, 1, 0, row_number+1, 0],
    'values':     [worksheet_name, 1, 2, row_number+1, 2],
    })

chart01.add_series({
    'name':       'Cached GB',
    'categories': [worksheet_name, 1, 0, row_number+1, 0],
    'values':     [worksheet_name, 1, 3, row_number+1, 3],
    })

chart01.add_series({
    'name':       'Memory Free GB',
    'categories': [worksheet_name, 1, 0, row_number+1, 0],
    'values':     [worksheet_name, 1, 4, row_number+1, 4],
    })

# Add a chart title and some axis labels.
chart01.set_title ({'name': 'Memore Usage for Server ' + hostname + ' in ' + location })
chart01.set_x_axis({'name': 'Monitoring Date'})
chart01.set_y_axis({'name': 'Memory in GB'})
#chart01.set_legend({'position': 'bottom'})
chart01.set_legend({'position': 'left'})

# Insert the chart into the worksheet (with an offset).
worksheet.insert_chart('G2', chart01, {'x_offset': 0, 'y_offset': 0, 'x_scale': 3, 'y_scale': 2})
workbook.close()
