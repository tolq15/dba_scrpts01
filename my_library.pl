#
# LT: 06/16/2011 Change from Windows to Linux.
# LT: 09/20/2011 Added HARD-CODED value for $ORACLE_HOME !!!
#

#====================#
# LIBRARY SUBROUTINS #
#====================#

sub Connect2Oracle
{
    my ($db_name) = @_;
    my $dbh;

    my $login_name = getpwuid($<);
    die "ERROR: YOU ARE NOT 'oracle'! WHO ARE YOU?\n"
        if ($login_name ne 'oracle');

    # should by in low case. "NVCSEA1" does not work
    $ENV{ORACLE_SID}  = lc $db_name;
    $ENV{ORACLE_HOME} = '/opt/oracle/product/11.0/db_1';
    $ENV{PATH}        = $ENV{PATH}.':'.$ENV{ORACLE_HOME}.'/bin';
    $dbh = DBI->connect('dbi:Oracle:', '', '',
                        { ora_session_mode => ORA_SYSDBA });

    return $dbh;
}


#========================================================#
# DIRECTORY STRUCTURE IS HARD-CODED HERE                 #
#========================================================#
# Generate file names for                                #
# SCRIPT_FULL_NAME - base script name with extension;    #
# SCRIPT_NAME      - base script name without extension; #
# EXTENSION        - script extension;                   #
# SCRIPT_DIR       - script directory;                   #
# CONFIG_FILE      - comfiguration file full name;       #
# PASSWD_FILE      - password file full name;            #
#========================================================#
sub SetConfCheckDouble
{
    my ($db_name, @in) = @_;

    my @out = ();
    my $ii  = 0;
    my %tmp_hash;

    my ($script_name, $script_dir, $script_ext) = fileparse($0, '\..*');
    $tmp_hash{'SCRIPT_NAME'}      = $script_name;
    $tmp_hash{'EXTENSION'}        = $script_ext;
    $tmp_hash{'SCRIPT_DIR'}       = $script_dir;
    $tmp_hash{'SCRIPT_FULL_NAME'} = $script_name . $script_ext;  # basename($0);
    $tmp_hash{'CONFIG_FILE'}      = $script_dir . "./config/" . $script_name . '.conf';

    foreach (@in)
    {
        $out[$ii++] = $tmp_hash{$_};
    }

    #=================================#
    # Read configuration file to hash #
    #=================================#
    my %config_params = ();

    tie %config_params, 'Config::IniFiles', ( -file => $tmp_hash{'CONFIG_FILE'});

    my $key_number = keys(%config_params);

    my $double_exec = CheckDoubleExecution($db_name, \%config_params, $tmp_hash{'SCRIPT_FULL_NAME'});

    return ($double_exec, \%config_params, @out);
}


sub Notify
{
    #=====================================================#
    # send the full error message to $mail_to             #
    # send the last line of the error message to $page_to #
    #=====================================================#
    my ($db_name, $subject, $hash_ref, @error_message) = @_;

    my $mail_to = ${$hash_ref}{$db_name}{'mail_to'};
    my $page_to = ${$hash_ref}{$db_name}{'page_to'};

    #return if (CheckSameMessageInterval($hash_ref, $db_name, $error_message[0]));
    return if (CheckSameMessageInterval($hash_ref, $db_name, $error_message[$#error_message]));

    # Send MAIL
    if (CheckMailBOW ($db_name, $hash_ref, "MAIL"))
    {
        SendMail ($subject, $mail_to, @error_message);
    }

    # Send PAGE. Last line of the message only.
    if (CheckMailBOW ($db_name, $hash_ref, "PAGE"))
    {
        SendMail ($subject, $page_to, $error_message[$#error_message]);
    }
}


sub SendMail
{
    my ($subject, $to, @text) = @_;

    print "Subject: $subject\n";
    print "Send to: $to\n";
    print "@text";

    if (! open(MAIL, "| mailx -s \"$subject\" $to >/dev/null 2>&1"))
    {
        print "ERROR: Can't send notification to $to\n: $!";
        exit 1;
    }

    print MAIL @text, "\n";
    close(MAIL);
}


#==============================================#
# Check that the same message will not be sent #
# in less than minimum interval seconds.       #
# Only last line will be checked.              #
#==============================================#
sub CheckSameMessageInterval
{
    my $hash_ref = shift;
    my $db_name  = shift;
    my $message  = shift;

    my $min_interval;
    my $last_message;
    my $last_message_sec;
    my $current_time = time;     # Current time from Epoch in seconds #

    $min_interval     = ${$hash_ref}{$db_name}{'min_interval'};
    $last_message     = ${$hash_ref}{$db_name}{'last_message'};
    $last_message_sec = ${$hash_ref}{$db_name}{'last_message_sec'};

    chomp $message;

    print << "EOD";
Min Interval: $min_interval
Last Message: $last_message
Current Mess: $message
Last Time   : $last_message_sec
Current Time: $current_time
EOD

    #===============================#
    # Check time after last message #
    #===============================#
    if (($last_message eq $message) and
        ($current_time - $last_message_sec <= $min_interval))
    {
        print "The same message in less then $min_interval sec. Do not send notification\n";
        return 1;
    }
    else
    {
        # Reset last time and message in Configuration file
        print "Reset last_message to\n$message\nReset last time to $current_time\n";
        ${$hash_ref}{$db_name}{'last_message'}     = $message;
        ${$hash_ref}{$db_name}{'last_message_sec'} = $current_time;
        tied( %{$hash_ref} )->RewriteConfig;

        return 0;
    }
}


sub CheckMailBOW
{
    my ($db_name, $hash_ref, $to) = @_;

    my $start;
    my $stop;
    my $BOW_status;
    my $current_time = time;     # Current time from Epoch in seconds #

    #=============================================================#
    # Reread config file again. This script runs for a long time. #
    # Values in configuration file can be changed.                #
    #=============================================================#
    $start = $to eq "MAIL" ? ${$hash_ref}{$db_name}{'BOW_mail_start'}
                           : ${$hash_ref}{$db_name}{'BOW_page_start'};
    $stop  = $to eq "MAIL" ? ${$hash_ref}{$db_name}{'BOW_mail_stop'}
                           : ${$hash_ref}{$db_name}{'BOW_page_stop'};

    #========================#
    # Check Block Out Window #
    #========================#
    if (( !defined $start ) or ( !defined $stop))
    {
        print "WARNING: BOW start or stop not defined.\n";

        # Notification should be send
        return 1;
    }

    # Notification should be send in this case also
    return 1 if (( !defined $start ) and ( !defined $stop));

    print "$to BOW Start: $start;\n$to BOW Stop : $stop;\n";

    #===================================================#
    # Convert start and stop time to seconds from Epoch #
    #===================================================#
    my ($mm_start, $dd_start, $yyyy_start, $hh_start, $mi_start, $ss_start) =
        ($start =~ /(\d+)-(\d+)-(\d+):(\d+):(\d+):(\d+)/);
    my ($mm_stop, $dd_stop, $yyyy_stop, $hh_stop, $mi_stop, $ss_stop) =
        ($stop  =~ /(\d+)-(\d+)-(\d+):(\d+):(\d+):(\d+)/);

    my $start_sec = timelocal ($ss_start, $mi_start, $hh_start, $dd_start, $mm_start-1, $yyyy_start-1900);
    my $stop_sec  = timelocal ($ss_stop,  $mi_stop,  $hh_stop,  $dd_stop,  $mm_stop-1,  $yyyy_stop-1900 );

    print "Start(sec):   $start_sec\nStop(sec) :   $stop_sec\nCurrent time: $current_time\n";

    #================================================================================#
    # If current time is between start/stop, then return 0 and send no notification. #
    # If current time is out of the window, return 1 to send notification.           #
    #================================================================================#
    if (($current_time > $start_sec) and ($current_time < $stop_sec))
    {
        $BOW_status = 0;
        print "Current time is in BOW. Do not send notification\n";
    }
    else
    {
        $BOW_status = 1;
        print "Current time is out of BOW. Do send notification\n";
    }

    return $BOW_status;
}


#=========================================================#
# Return 0 if there is no double execution and we can     #
# continue with current script. Return 1 if current run   #
# should be canceled.                                     #
# Current script should continue if in configuration file #
# we have Status = Done and there is no runing process    #
# with PID equal PID in configuration file.               #
#=========================================================#
sub CheckDoubleExecution ()
{
    my ($db_name, $hash_ref, $script_name) = @_;

    my $Status_Done   = 'Done';
    my $Status_Runing = 'Runing';

    my $RC = 0;
    
    return $RC;

    # ====================================#
    # ==================================# #
    # THE REST IS IRRELEVANT IN WINDOWS # #
    # ==================================# #
    # ====================================#
    
    print "CheckDoubleExecution: BEGIN\n";
    print "CheckDoubleExecution: END\n";

    my $pid       = ${$hash_ref}{$db_name}{'PID'};
    my $status    = ${$hash_ref}{$db_name}{'Status'};
    my $start_sec = ${$hash_ref}{$db_name}{'StartTime'};
    my $max_time  = ${$hash_ref}{$db_name}{'MaxTime'};
    print "PID: $pid\nStatus: $status\nStart Time: $start_sec\nMax Run: $max_time\n";

    my $current_time = time;     # Current time from Epoch in seconds #

    #====================================================================#
    # Check if process is running. CHECK FOR NON PORTABLE 'GREP' OPTIONS #
    #====================================================================#
    # Replace '.' in file name with '\.' to use in regular expression
    $script_name =~ s/\./\\\./;

    my $count = 0;

    open (PS, "ps -ef |") or die "ERROR: Can not fork 'ps': $!";
    while (<PS>)
    {
        $count++ if (m/\b$pid\b.+$script_name/);
    }

    close (PS);
    
    #===============================#
    # Check Status&PID combinations #
    #===============================#
    if ($count == 0)
    {
        if ($status eq $Status_Done)
        {
            print "Last executions finished successfully.\n";
        }
        else
        {
            print "Status is Runing, but process $pid is not running.\n";
            print "Last run of the script failed.\n";
        }
        
        print "Write current process info in configuration file...\n";
        RewriteConfigFile ($db_name, $hash_ref, 'Start') ||
            die "ERROR: rewriting Config File: @Config::IniFiles::errors\n";
    }
    elsif ($count == 1)
    {
        if (($status eq $Status_Runing) && ($start_sec + $max_time > $current_time))
        {
            print "Execution time do not expired. Terminate current process.\n";
            $RC = 1;
        }
        else
        {
            print "Status is $status, process $pid is still running.\n";
            
            if ($status eq $Status_Done)
            {
                print "Possible run-away process.\n";
            }
            else # $status eq $Status_Runing
            {
                print "Execution time expired.\n";
            }           

            print "Try to terminate process $pid.\nWrite new info in config file.\n";

            # terminate old script. See also page 584 in Cookbook
            my $processes_killed = kill 9 => $pid;
            chomp $processes_killed;
        
            if ($processes_killed)
            {
                print "$processes_killed process (PID = $pid) was killed.\n";
                RewriteConfigFile ($db_name, $hash_ref, 'Start') ||
                    die "ERROR: rewriting Config File: @Config::IniFiles::errors\n";
            }
            else
            {
                print "ERROR: Could not kill run-away process $pid.\n";
                print "ERROR: Terminate current script.\n";
                # SEND MAIL !!!!
                $RC = 1;
            }
        }
    }
    else # $count > 1
    {
        print "ERROR: Command \'ps\' returned $count processes with PID = $pid.\n";
        print "ERROR: Terminate current script. CHECK YOUR SYSTEM!!!\n";
        # SEND MAIL !!!!
        $RC = 1;
    }

    print "CheckDoubleExecution: END\n";
    return $RC;
}


sub RewriteConfigFile
{
    my ($db_name, $hash_ref, $action)  = @_;

    print "RewriteConfigFile: BEGIN\n";

    if ($action eq 'Start')
    {
        #====================================================#
        # Write new PID, Status and Start_Sec in config file #
        #====================================================#
        ${$hash_ref}{$db_name}{'PID'}       = $$;
        ${$hash_ref}{$db_name}{'Status'}    = 'Runing';
        ${$hash_ref}{$db_name}{'StartTime'} = time;
    }
    else # $action eq 'Exit'
    {
        ${$hash_ref}{$db_name}{'Status'}    = 'Done';
    }

    print "RewriteConfigFile: END\n";

    return tied( %{$hash_ref} )->RewriteConfig;
}

sub RewriteConfigFileNew
{
    my ($db_name, $hash_ref, $entry, $value)  = @_;

    ${$hash_ref}{$db_name}{$entry} = $value;

    return tied( %{$hash_ref} )->RewriteConfig;
}

1;
