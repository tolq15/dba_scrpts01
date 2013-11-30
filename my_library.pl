#
# LT: 06/16/2011 Change from Windows to Linux.
# LT: 09/20/2011 Added HARD-CODED value for $ORACLE_HOME !!!
# LT: 11/05/2013 All environment variables are defined in .bash_profile_cron file
#
# TODO:
# 1. Remove $ENV{...} from Connect2Oracle
# 2. Use SendMail in some scrips to use mailx.
# 3. Create sub to check DB role.
#=============================================================

#====================#
# LIBRARY SUBROUTINS #
#====================#

sub Connect2Oracle
{
    my ($db_name) = @_;
    my $dbh;

    # Only Oracle user 'oracle' can login!
    my $login_name = getpwuid($<);
    die "ERROR: YOU ARE NOT 'oracle'! WHO ARE YOU?\n"
        if ($login_name ne 'oracle');

    # Connect as sysdba
    $dbh = DBI->connect('dbi:Oracle:', '', '',
                        { ora_session_mode => ORA_SYSDBA });

    return $dbh;
}


sub GetConfig
{
    use Config::IniFiles;

    # Generate configuration file name based on script name.
    # Directory structure and config file extension are hard-coded here.
    # $script_name - name of the script without extension.
    my ( $script_name, $script_dir, $script_ext ) = fileparse( $0, '\..*' );

    # $ENV{WORKING_DIR} allows to change directory between
    # calls to GetConfig and RewriteConfigFile.
    my $config_file_name = $ENV{WORKING_DIR} . "/config/" . $script_name . '.conf';

    # Read configuration file into hash
    my %config_params = ();
    tie %config_params, 'Config::IniFiles', ( -file => $config_file_name );

    return \%config_params;
}


sub RewriteConfigFile
{
    my ($db_name, $hash_ref, $entry, $value)  = @_;

    ${$hash_ref}{$db_name}{$entry} = $value;

    return tied( %{$hash_ref} )->RewriteConfig;
}


sub CheckDBRole
{
    my ($db_name) = @_;

    my $file_name = $ENV{DB_ROLE_FILE};
    open (ROLE, $file_name) || die "my_library::CheckDBRole: Failed to open $file_name: $!\n";

    my $role = <ROLE>;
    close ROLE;
    return $role;
}


sub SendAlert
{
    my ($the_server, $the_db_name, $the_subject, $the_message) = @_;
    my $sender = new Mail::Sender;
    (ref ($sender->MailMsg
          (
           {
            to      => $ENV{TO},
            from    => basename ($0) .'@'. $the_server,
            smtp    => $ENV{SMTP},
            subject => $the_subject,
            msg     => $the_message,
           }
          )
         )  and print "Mail sent OK.\n$the_message\n"
    )    or die "Mail Sender Error: $Mail::Sender::Error\n$the_message";
}

1;
