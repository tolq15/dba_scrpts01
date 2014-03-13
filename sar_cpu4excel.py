#!python
#==========================================================#
# Read CPU stats from SAR files from /var/log/sa
# (default SAR log direstory)
# and generate Excel spreadsheet with the data and charts.
#
# Configuration file added
# [CPU]
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

# Generate output file name
location   = os.environ['GE0_LOCATION']
hostname   = os.uname()[1]
headers    = config_param.get('CPU', 'column_headers').split(',')
excel_file = config_param.get('CPU', 'output_dir') + script_name + '_' + location + '_'+hostname + '_' + os.environ['THE_TIME'] + '.xlsx'
data_file  = config_param.get('CPU', 'output_dir')

# Setup spreadsheet
workbook        = xlsxwriter.Workbook(excel_file)
bold            = workbook.add_format({'bold': 1})
row_number      = 0
start_reading   = 0
column_headers  = 0
file_timestamp  = ''
worksheet_list  = {}
file_name_list  = {}
worksheet_names = []

#-------------------------------------------#
# Read SAR log files in chronological order #
#-------------------------------------------#
# go to SAR directory
os.chdir(config_param.get('CPU', 'sar_dir'))

# List all files in this directory in chrono order
all_sar_files = sorted(filter(os.path.isfile, os.listdir('.')), key=os.path.getmtime)

# List only 'sar' files (text files)
text_files = [text_files for text_files in all_sar_files if re.match('^sar.*', text_files)]

#--------------------------------------------------------------#
# Read all memory stats data from SAR log files into one array #
#--------------------------------------------------------------#

# Looks at string
# old
# 00:00:01   CPU   %user  %nice   %system   %iowait    %steal     %idle
# new
# 00:00:01   CPU   %usr   %nice    %sys   %iowait    %steal    %irq     %soft    %guest %idle
# and read untill string starting with 'Average'
for the_line in fileinput.input(text_files):
    # Skip empty strings
    if the_line.isspace():
        continue
    # Read the first line of each file to find the date
    # Linux 2.6.32-100.0.19.el5 (STPHORACLEDB05)      2013-09-19
    match_obj = re.match('Linux\s.*\s(\d{4}-\d\d-\d\d)$', the_line)
    if match_obj:
        file_timestamp =  match_obj.groups()[0]
        continue
    
    # Start record the data
    if re.match('.*iowait.*', the_line):
        # Set the flag
        start_reading = 1
        # Populate header once only
        if column_headers == 0:
            column_headers = 1
        continue
    
    # Stop record the data
    if re.match('^Average.*', the_line) and start_reading == 1:
        start_reading = 0
        continue

    # Record the data
    if start_reading == 1:
        # Skip all next headers
        if re.match('.*iowait.*', the_line):
            continue
        # Compose data row
        row_data = the_line.rstrip('\n').split()
        row_number += 1
        # Generate worksheet name
        worksheet = 'CPU000'[:-len(row_data[1])] + row_data[1]
        # Bug in 'sa' (?)
        if float(row_data[5]) > 99.99:
            print 'Bug(?): ', file_timestamp, row_data[0], worksheet, 'iowait: ', row_data[5] 
            row_data[5] = '0.0'
        # Keep only data required for charts
        the_data = ( file_timestamp + " " + row_data[0] # time
                    ,float(row_data[2])                 # %user
                    ,float(row_data[4])                 # %systen
                    ,float(row_data[5])                 # %iowait
                    ,float(row_data[7]))                # %idel

        #-----------------------------------------#
        # Write data to new or existing worksheet #
        #-----------------------------------------#
        if worksheet in worksheet_names:
            # All worksheets were created and first two rows inserted.
            # Find next row number
            excel_row_number = row_number//len(worksheet_names)+1
            worksheet_list[worksheet].write_row(excel_row_number, 0, the_data)
            # Write data to output file in reverce order
            file_name_list[worksheet].write(file_timestamp + " " + row_data[0] + "," # date
                                            +format(float(row_data[7]),"5.2f") + "," # %user
                                            +format(float(row_data[5]),"5.2f") + "," # %systen
                                            +format(float(row_data[4]),"5.2f") + "," # %iowait
                                            +format(float(row_data[2]),"5.2f") + "\n") # %idel
        else:
            # Create new worksheet and record to the hash.
            # Hash key is sheet name, hash value is worksheet object
            worksheet_list[worksheet] = workbook.add_worksheet(worksheet)
            # Create new output file name and record to the hash.
            # Hash key is sheet name, hash value is output file discriptor (?)
            file_name_list[worksheet] = open(data_file + worksheet + '.csv', "w")
            # Adjust the column width for date.
            worksheet_list[worksheet].set_column(0, 0, 20)
            # Insert the first two rows into spreadsheet
            worksheet_list[worksheet].write_row('A1', headers, bold)
            worksheet_list[worksheet].write_row('A2', the_data)
            # Add sheet name to the list
            worksheet_names.append(worksheet)
            # Write data to output file in reverce order
            file_name_list[worksheet].write(config_param.get('CPU','column_headers_csv') + "\n")
            file_name_list[worksheet].write(file_timestamp + " " + row_data[0] + "," # date
                                            +format(float(row_data[7]),"5.2f") + "," # %user
                                            +format(float(row_data[5]),"5.2f") + "," # %systen
                                            +format(float(row_data[4]),"5.2f") + "," # %iowait
                                            +format(float(row_data[2]),"5.2f") + "\n") # %idel

row_number = row_number/len(worksheet_names)
print 'Each Sheet has', row_number, 'rows'

#----------------------------------#
# Excel data is ready              #
# Generate chart in each worksheet #
#----------------------------------#

for the_worksheet in workbook.worksheets():
    the_name = the_worksheet.get_name()
    chart01  = workbook.add_chart({'type': 'area', 'subtype': 'stacked'})

    # Configure the series.
    # List is [ sheet_name, first_row, first_col, last_row, last_col ].
    chart01.add_series({
        'name':       'Time in User Mode',
        'categories': [the_name, 1, 0, row_number, 0],
        'values':     [the_name, 1, 1, row_number, 1],
    })

    chart01.add_series({
        'name':       'Time in System Mode',
        'categories': [the_name, 1, 0, row_number, 0],
        'values':     [the_name, 1, 2, row_number, 2],
    })

    chart01.add_series({
        'name':       'IO Wait Time',
        'categories': [the_name, 1, 0, row_number, 0],
        'values':     [the_name, 1, 3, row_number, 3],
    })

    chart01.add_series({
        'name':       'Idel Time',
        'categories': [the_name, 1, 0, row_number, 0],
        'values':     [the_name, 1, 4, row_number, 4],
    })

    # Add a chart title and some axis labels.
    chart01.set_title ({'name': 'CPU Usage for Server ' + hostname + ' in ' + location })
    chart01.set_x_axis({'name': 'Monitoring Date'})
    chart01.set_y_axis({'name': 'Time in %'})
    chart01.set_legend({'position': 'bottom'})

    # Insert the chart into the worksheet (with an offset).
    the_worksheet.insert_chart('H1', chart01, {'x_offset': 0, 'y_offset': 0, 'x_scale': 3, 'y_scale': 2})

workbook.close()
