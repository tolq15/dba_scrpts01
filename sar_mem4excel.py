#==========================================================#
# Read memory stats from SAR files from /var/log/sa
# (default SAR log direstory)
# and generate Excel spreadsheet with the data and charts.

# TODO: 1. parameter for non-default SAR log directory,
# or put it to config file;
#==========================================================#
import os
import re
from datetime import datetime
import fileinput
import xlsxwriter

# HARD-CODED!!!
sar_dir = '/var/log/sa'
location = 'Seattle'
# hostname = os.getenv('HOSTNAME')
# Command above does not work from cron. It return 'None'.
# But it works from command line.
# It looks like os.getenv require some environment settings.

# Generate output file name
timestamp = datetime.now().strftime("%Y%m%d")
hostname = os.uname()[1]
output_dir = '/home/oracle/scripts/Excel/'
excel_file = output_dir + 'sar_mem4excel_' + location + '_' + hostname + '_' + timestamp + '.xlsx'
column_headers = ('Date'
                  ,'Free Memory'
                  ,'Used Memore'
                  ,'Buffers'
                  ,'Cached'
                  ,'Free Swap'
                  ,'Used Swap'
                  ,'Swap Cad')
workbook  = xlsxwriter.Workbook(excel_file)
worksheet_name = 'Memory Usage'
worksheet = workbook.add_worksheet(worksheet_name)
bold      = workbook.add_format({'bold': 1})
file_timestamp = ''
column_headers_done = 0
excel_data = []
row_number = 0

read_following_lines = 0

#-------------------------------------------#
# Read SAR log files in chronological order #
#-------------------------------------------#
# go to SAR directory
os.chdir(sar_dir)

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
        read_following_lines = 1
        # Populate header once only
        if column_headers_done == 0:
            worksheet.write_row('A1', column_headers, bold)
            column_headers_done = 1
            #print column_headers
        continue
    
    # Stop record the data
    if re.match('^Average.*', the_line) and read_following_lines == 1:
        read_following_lines = 0
        continue

    # Record the data
    if read_following_lines == 1:
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
