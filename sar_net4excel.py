#!python
#==========================================================#
# Read Network stats from SAR files from /var/log/sa
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
excel_file = output_dir+'sar_net4exce_'+location +'_'+ hostname+'_'+timestamp+'.xlsx'
worksheet_dir = {}
column_headers = ('Date'
                  ,'IFACE'
                  ,'packets received per second'
                  ,'transmitted packets per second'
                  ,'bytes received per second'
                  ,'bytes transmitted per second')
workbook  = xlsxwriter.Workbook(excel_file)
nic_names = ('eth0','eth1','eth2','eth3','lo')

for the_nic_name in (nic_names):
    # create dictionary with key = nic_name and value = worksheet
    worksheet_dir[the_nic_name] = workbook.add_worksheet(the_nic_name)

bold = workbook.add_format({'bold': 1})
file_timestamp = ''
row_number      = 0
file_row_number = 0
column_headers_done  = 0
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
# 00:00:01    # IFACE   rxpck/s   txpck/s   rxbyt/s   txbyt/s   rxcmp/s   txcmp/s  rxmcst/s
# and read untill string starting with 'Average'
for the_line in fileinput.input(text_files):
    # Read the first line of each file to find the date
    # Linux 2.6.32-100.0.19.el5 (STPHORACLEDB05)      2013-09-19
    match_obj = re.match('Linux\s.*\s(\d{4}-\d\d-\d\d)$', the_line)
    if match_obj:
        file_timestamp =  match_obj.groups()[0]+':'
        continue
    
    # Start record the data
    if re.match('.*\sIFACE\s*rxpck/s\s.*', the_line):
        # Set the flag
        read_following_lines = 1
        # Populate each worksheet header once only
        if column_headers_done == 0:
            for the_worksheet in workbook.worksheets():
                the_worksheet.write_row('A1', column_headers, bold)
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
        if re.match('.*\sIFACE\s.*', the_line):
            continue
        # Convert strings to numbers
        row_data = (file_timestamp+the_line.rstrip('\n')).split()
        for idx in range(len(column_headers)):
            if row_data[idx].replace('.','',1).isdigit():
                row_data[idx] = float(row_data[idx])
        row_number = (file_row_number // len(nic_names)) + 1
        file_row_number += 1
        
        # Write rows in correspondent worksheets
        worksheet_dir[row_data[1]].write_row(row_number, 0, row_data[0:len(column_headers)])
        #print row_data
        #break

#print the_data
print row_number

#---------------------#
# Excel data is ready #
# Generate chart      #
#---------------------#

# Configure the series for each worksheet.
# List is [ sheet_name, first_row, first_col, last_row, last_col ].
for the_worksheet in workbook.worksheets():
    the_name = the_worksheet.get_name()

    # Create first chart
    chart01 = workbook.add_chart({'type': 'line'})

    chart01.add_series({
        'name': 'Packets Receiced Per Second',
        'categories':[the_name, 1, 0, row_number, 0],
        'values':[the_name, 1, 2, row_number, 2],
    })

    chart01.add_series({
        'name':'Packets Transmited Per Second',
        'categories':[the_name, 1, 0, row_number, 0],
        'values':[the_name, 1, 3, row_number, 3],
    })
    # Add a chart title and some axis labels.
    chart01.set_title ({'name': the_name + ' Network Traffic for Server ' + hostname + ' in ' + location })
    chart01.set_x_axis({'name': 'Monitoring Date'})
    chart01.set_y_axis({'name': 'Packets Per Second'})
    chart01.set_legend({'position': 'bottom'})

    # Insert the chart into the worksheet (with an offset).
    the_worksheet.insert_chart('H1'
                               , chart01
                               , {'x_offset': 0, 'y_offset': 0, 'x_scale': 3, 'y_scale': 2}
                              )

    # Create second chart
    chart02 = workbook.add_chart({'type': 'line'})

    chart02.add_series({
        'name': 'Bytes Received Per Second',
        'categories':[the_name, 1, 0, row_number, 0],
        'values':[the_name, 1, 4, row_number, 4],
    })

    chart02.add_series({
        'name':'Bytes Transmited Per Second',
        'categories':[the_name, 1, 0, row_number, 0],
        'values':[the_name, 1, 5, row_number, 5],
    })
    # Add a chart title and some axis labels.
    chart02.set_title ({'name': the_name + ' Network Traffic for Server ' + hostname + ' in ' + location })
    chart02.set_x_axis({'name': 'Monitoring Date'})
    chart02.set_y_axis({'name': 'Bytes Per Second'})
    chart02.set_legend({'position': 'bottom'})

    # Insert the chart into the worksheet (with an offset).
    the_worksheet.insert_chart('H31'
                               , chart02
                               , {'x_offset': 0, 'y_offset': 0, 'x_scale': 3, 'y_scale': 2}
                              )

workbook.close()
