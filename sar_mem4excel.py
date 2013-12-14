#==========================================================#
# Read memory stats from SAR files from /var/log/sa
# (default SAR log direstory)
# and generate Excel spreadsheet with the data and charts.

# TODO: 1. parameter for non-default SAR log directory,
# or put it to config file;
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
config_param = ConfigParser.RawConfigParser()
config_param.read('./config/' + script_name + '.conf')

# Generate output file name
location   = os.environ['GE0_LOCATION']
hostname   = os.uname()[1]
excel_file = config_param.get('MEMORY', 'output_dir') + script_name + '_' + location + '_'+hostname + '_' + os.environ['THE_TIME'] + '.xlsx'

# Setup spreadsheet
file_timestamp = ''
worksheet_name = 'Memory Usage'
workbook       = xlsxwriter.Workbook(excel_file)
worksheet      = workbook.add_worksheet(worksheet_name)
bold           = workbook.add_format({'bold': 1})
column_headers = 0
row_number     = 0
start_reading  = 0
excel_data     = []

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
    # Linux 2.6.32-100.0.19.el5 (STPHORACLEDB05)      2013-09-19
    m_obj = re.match('Linux\s.*\s(\d{4}-\d\d-\d\d)$', the_line)
    if m_obj:
        file_timestamp =  m_obj.groups()[0]+':'
        continue
    
    # Start record the data
    if re.match('.*\skbmemfree\s.*', the_line):
        # Set the flag
        start_reading = 1
        # Populate header once only
        if column_headers == 0:
            worksheet.write_row('A1', config_param.get('MEMORY','column_headers').split(','), bold)
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
        # Convert strings to numbers
        row_data = (file_timestamp+the_line.rstrip('\n')).split()
        for idx in range(len(row_data)):
            if row_data[idx].replace('.','',1).isdigit():
                # ! NOT ALL COLUMNS SHOULD BE IN 'GB' !
                row_data[idx] = round(float(row_data[idx])/1024/1024,2)
        row_number += 1
        # Keep only data required for charts
        # columns 0,1,2-(4+5),4,5,6,7,9
        the_data = ( row_data[0]
                    ,row_data[1]
                    ,row_data[2]-row_data[4]-row_data[5]
                    ,row_data[4]
                    ,row_data[5]
                    ,row_data[6]
                    ,row_data[7]
                    ,row_data[9])
        worksheet.write_row(row_number, 0, the_data)
        #print the_data
        #break
        
#---------------------#
# Excel data is ready #
# Generate chart      #
#---------------------#
#print excel_data
print row_number

chart01 = workbook.add_chart({'type': 'area', 'subtype': 'stacked'})

# Configure the series.
# List is [ sheet_name, first_row, first_col, last_row, last_col ].
chart01.add_series({
    'name':       'Memory Used GB',
    'categories': [worksheet_name, 1, 0, row_number, 0],
    'values':     [worksheet_name, 1, 2, row_number, 2],
    })

chart01.add_series({
    'name':       'Memory Free GB',
    'categories': [worksheet_name, 1, 0, row_number, 0],
    'values':     [worksheet_name, 1, 1, row_number, 1],
    })

chart01.add_series({
    'name':       'Buffers GB',
    'categories': [worksheet_name, 1, 0, row_number, 0],
    'values':     [worksheet_name, 1, 3, row_number, 3],
    })

chart01.add_series({
    'name':       'Cached GB',
    'categories': [worksheet_name, 1, 0, row_number, 0],
    'values':     [worksheet_name, 1, 4, row_number, 4],
    })

# Add a chart title and some axis labels.
chart01.set_title ({'name': 'Memore Usage for Server ' + hostname + ' in ' + location })
chart01.set_x_axis({'name': 'Monitoring Date'})
chart01.set_y_axis({'name': 'Memory in GB'})
chart01.set_legend({'position': 'bottom'})

# Insert the chart into the worksheet (with an offset).
worksheet.insert_chart('J1', chart01, {'x_offset': 0, 'y_offset': 0, 'x_scale': 3, 'y_scale': 2})
workbook.close()
