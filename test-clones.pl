#!/usr/bin/perl

# Initialize
use Getopt::Std;
use Config::IniFiles;
use threads;
use threads::shared;
use Switch;

# Get the arguments
getopts('he:c:uv:', \%opts);

# Command-line checking
if ( $opts{'h'} ) {
    DoHelp( "ShowHelp" );
    exit( 0 );
}
unless( $opts{'c'} ) {
    DoHelp( "ConfigFile" );
    exit( 2 );
}
unless( $opts{'v'} ) {
    DoHelp( "version" );
    exit( 2 );
} else {
    unless ( $opts{'v'} =~ /stage|live/ ) {
        DoHelp( "version" );
        exit( 2 );
    }
}
if ( ( $opts{'u'} ) || ( $opts{'p'} ) ) {
    print "\n\nIncorrect usage!  Did you mean to call clone.pl instead?\n\n\n";
    exit( 1 );
}

tie %cfg, 'Config::IniFiles', ( -file => "$opts{'c'}" );

# This is to be sure that the test doesn't fail due to a known SSH bug in RedHat
system( "rm -rf /tmp/ssh*" );


print "\nPreparing to test all targets defined in configuration file \"$opts{'c'}\" for $opts{'v'} clones.\n\nPlease wait, this may take a while. Results will be displayed once complete.\n\n";
    open( SQL_SCRIPT, ">", "/tmp/user_icm_runner_get_hash.sql" );
    print SQL_SCRIPT <<EOP;
set feedback off
set heading off
set echo off
set newpage 0
select password from sys.user\$ where name= 'USER_ICM_RUNNER';
EOP
    close( SQL_SCRIPT );
    open( SQL_SCRIPT, ">", "/tmp/user_icm_runner_test_lock.sql" );
    print SQL_SCRIPT <<EOP;
set feedback off
set heading off
set echo off
set newpage 0
select account_status from dba_users where username = 'USER_ICM_RUNNER';
EOP
    close( SQL_SCRIPT );
    open( SQL_SCRIPT, ">", "/tmp/fingerprint.sql" );
    print SQL_SCRIPT <<EOP;
set feedback off
set heading off
set echo off
set newpage 0
SELECT RULE_ENGINE.UTILS.RULES_FINGERPRINT FROM DUAL;
EOP
    close( SQL_SCRIPT );

# Log this test run with a header
$current_date = `date +%Y-%m-%d`;
$current_time = `date +%I:%M:%S`;
chomp( $current_date, $current_time );
open( TEST_LOG, ">>", "logs/test-clones.log" ) or warn( "Could not open test-clones.log for writing: $!\n" );
print TEST_LOG "=================================================================================\n";
print TEST_LOG "INFO: Beginning testing of clones at $current_date $current_time\n";
close( TEST_LOG );

# Prepare MySQL connection
use DBI;
my $dbh = DBI->connect("DBI:mysql:database=rapid_release;host=localhost", "rls", "rls", {'RaiseError' => 0});

    
# This counter is just so the test log only has one entry for the master.  There is no case where any one ini uses different masters.
$current_target_count = 1;
$previous_clone_source = 'NONE';
foreach $current_target ( keys %cfg ) {
    #print "Testing $current_target..\n";
    if ( $opts{'v'} =~ 'stage' ) {
        $test_ip = $cfg{$current_target}{'ipaddr'};
    } else {
        $test_ip = $cfg{$current_target}{'liveipaddr'};
    }
    #print "Local Hostname: ";
    $temp = `ssh -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no $test_ip 'echo \$HOSTNAME' 2>/dev/null`;
    $temp =~ s/\s+//g;
    $results{$current_target}[0] = $temp;
    $temp = `ssh -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no $test_ip 'ip -br a show dev ens32' 2>/dev/null`;
    @parts = split( /\s+/, $temp );
    $temp = $parts[2];
    $results{$current_target}[1] = $temp;
    $oracle_status = `ssh -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no $test_ip "su - oracle -c 'lsnrctl status | grep Service | grep -v 11G | grep -v PLSExt | grep -v Summary'" 2>/dev/null`;
	while ( $test_count < 2 ) {
		if ( $oracle_status =~ /RLS/  ) {
			last;
		} else {
			#print "Detected Oracle didn't start on $current_target.  Attempting to start now...\n";
			`ssh -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no $test_ip 'service dbora start' 2>/dev/null`;
			$oracle_status = `ssh -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no $test_ip "su - oracle -c 'lsnrctl status | grep Service | grep -v 11G | grep -v PLSExt | grep -v Summary'" 2>/dev/null`;
			$test_count++;
			next;
		}
	}
	unless ( $oracle_status =~ /RLS/ ) {
		system( "ssh -oConnectTimeout=3 -oStrictHostKeyChecking=no $test_ip 'reboot'" );
		print "Oracle not startable on $current_target.  Rebooting. Please run test again in ~5 minutes..\n";
	}
    # Get user_icm_runner password hash
    system( "scp -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no /tmp/user_icm_runner_get_hash.sql $test_ip:/tmp/user_icm_runner_get_hash.sql 2>1 > /dev/null" );
    $user_icm_runner_hash_result = `ssh -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no $test_ip "su - oracle -c 'echo @/tmp/user_icm_runner_get_hash.sql | sqlplus -S / as sysdba'" 2>/dev/null`;
	
	$results{$current_target}[3] = "UNKNOWN";
	if ( $user_icm_runner_hash_result == '9B4AD08E857FC3C1' ) {
		$results{$current_target}[3] = "Prod Value";
	}
	if ( $user_icm_runner_hash_result == '3EE9CE226D1DD442' ) {
		$results{$current_target}[3] = "Open/Test Value";
	}
	if ( $user_icm_runner_hash_result == 'EF892625E87AB00C' ) {
		$results{$current_target}[3] = "QA Value";
	}
    
    ## Test for user_icm_runner lock status
    #system( "scp -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no /tmp/user_icm_runner_test_lock.sql $test_ip:/tmp/user_icm_runner_test_lock.sql 2>1 > /dev/null" );
	#$user_icm_runner_lock_result = `ssh -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no $test_ip "su - oracle -c 'echo @/tmp/user_icm_runner_test_lock.sql | sqlplus -S / as sysdba'" 2>/dev/null`;
    #$results{$current_target}[4] = $user_icm_runner_lock_result;


	# Get Oracle Service Name
    $oracle_status =~ s/\s+//g;
    @parts = split( /\"/, $oracle_status );
    $service_name = $parts[1];
    $results{$current_target}[2] = $service_name;
    
	# Get Creation Timestamp
    $datestamp_from_clone = `ssh -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no $test_ip "cat /root/datestamp.txt" 2>/dev/null`;
	$results{$current_target}[5] = $datestamp_from_clone;
	
	# Register the source of the clone
	$clone_source = $cfg{$current_target}{'source'};
	$results{$current_target}[6] = $clone_source;
	
	if ( $previous_clone_source ne $clone_source ) {
		# Clone source Fingerprint
		# Register the current clone as the "previous" to determine if we need to re-fingerprint for the next
		$previous_clone_source = $clone_source;
		# Check the host name just in case the source is a non-golden master and mofiy accordingly so we can ssh in as expected
		if ( $clone_source =~ /_/ ) {
			( $short_clone_source ) = split( /_/, $clone_source );
		} else {
			$short_clone_source = $clone_source;
		}
		system( "scp -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no /tmp/fingerprint.sql $clone_source:/tmp/fingerprint.sql 2>1 > /dev/null" );
		#$source_app_version = `ssh -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no $short_clone_source "su - oracle -c \'echo \@/tmp/fingerprint.sql \| sqlplus -S / as sysdba\'" 2>/dev/null`;
		$source_app_version = `ssh -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no $short_clone_source "su - oracle -c 'echo @/tmp/fingerprint.sql | sqlplus -S / as sysdba'" 2>/dev/null`;
		$source_app_version =~ s/\n//g;
	}
	
	if ( $current_target_count == 1 ) {
		open( TEST_LOG, ">>", "logs/test-clones.log" ) or warn( "Could not open test-clones.log for writing: $!\n" );
		print TEST_LOG "INFO: MASTER: Fingerprint for $clone_source: $source_app_version\n";
		close( TEST_LOG );
		$current_target_count++;
	}
	
	# Fingerprint for each clone
	system( "scp -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no /tmp/fingerprint.sql $test_ip:/tmp/fingerprint.sql 2>1 > /dev/null" );
	$app_version = `ssh -oConnectTimeout=3 -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no $test_ip "su - oracle -c 'echo @/tmp/fingerprint.sql | sqlplus -S / as sysdba'" 2>/dev/null`;
	$app_version =~ s/\n//g;
	if ( $app_version eq $source_app_version ) {
		$results{$current_target}[7] = "PASSED";
		$pass_fail = "PASS";
		push( @passed_list, $current_target );
		open( TEST_LOG, ">>", "logs/test-clones.log" ) or warn( "Could not open test-clones.log for writing: $!\n" );
		print TEST_LOG "INFO: PASSED: Fingerprint for $current_target: $app_version\n";
		close( TEST_LOG );
	} else {
		$results{$current_target}[7] = "FAILED";
		$pass_fail = "FAIL";
		push( @failed_list, $current_target );
		open( TEST_LOG, ">>", "logs/test-clones.log" ) or warn( "Could not open test-clones.log for writing: $!\n" );
		print TEST_LOG "ERROR: FAILED: Fingerprint for $current_target: $app_version\n";
		close( TEST_LOG );
	}
	
	# Extract software and policy base versions for comparison
	
	# Master Software and policy base versions
	( $mapp, $mdata, @junk ) = split( /,/, $source_app_version );
	( $junk, $master_software_version ) = split( /=/, $mapp );
	( $junk, $master_policy_version ) = split( /=/, $mdata );
	
	# Current target software and policy base versions
	( $app, $data, @junk ) = split( /,/, $app_version );
	( $junk, $software_version ) = split( /=/, $app );
	( $junk, $policy_version ) = split( /=/, $data );
	
	# Compare them and register the results
	if ( ( $master_software_version eq $software_version ) && ( $master_policy_version eq $policy_version )) {
		$results{$current_target}[8] = "MATCHED";
	} else {
		$results{$current_target}[8] = "MISS-MATCHED";
	}
	
	my $query = sprintf("INSERT INTO test_log ( tl_vm_name, tl_pass_fail, tl_test_timestamp, tl_master_fingerprint, tl_fingerprint, tl_master ) VALUES (%s, %s, %s, %s, %s, %s)",
                    $dbh->quote("$current_target"), $dbh->quote("$pass_fail"), $dbh->quote("$current_date $current_time"), $dbh->quote("$app_version"), $dbh->quote("$source_app_version"), $dbh->quote("$short_clone_source") );
	$dbh->do($query);
}

# Log this test run with a trailer
$current_date = `date +%Y-%m-%d`;
$current_time = `date +%I:%M:%S`;
chomp( $current_date, $current_time );
open( TEST_LOG, ">>", "logs/test-clones.log" ) or warn( "Could not open test-clones.log for writing: $!\n" );
print TEST_LOG "INFO: Ending testing of clones at $current_date $current_time\n";
print TEST_LOG "=================================================================================\n";
close( TEST_LOG );

# Disconnect from MySQL
$dbh->disconnect();

print <<EOS;
Summary:
===========================================================================================================================================================================
|     Host Name         |   Service Name    |    IP Address     |    Password Hash      | Creation Timestamp |    Clone Source    | Fingerprint Match?|  APP/DATA Match?  |
|  (NOT be all caps)    | (Oracle Instance) |                   |  (All should match!)  |                    |                    |                   |                   |
===========================================================================================================================================================================
EOS

format STDOUT = 
| @|||||||||||||||||||| | @|||||||||||||||| | @|||||||||||||||| | @|||||||||||||||||||| | @||||||||||||||||| | @||||||||||||||||| |@|||||||||||||||||| |@|||||||||||||||| |
$results{$current_target}[0], $results{$current_target}[2], $results{$current_target}[1], $results{$current_target}[3], $results{$current_target}[5], $results{$current_target}[6], $results{$current_target}[7], $results{$current_target}[8]
===========================================================================================================================================================================
.

foreach $current_target ( keys %cfg ) {
    write;
}

print "\n";

if ( $opts{'e'} ) {
	$to = $opts{'e'};
	$from = 'root';
	$subject = "Test clone results from $opts{'c'} ";
	$message = "Clone test from $opts{'c'} completed on $current_date at $current_time.\n\nFAILED CLONES:\n";
	foreach $failure ( @failed_list ) {
		$message .= "$failure\n";
	}
	$message .= "\n\nPASSED CLONES:\n";
	foreach $pass ( @passed_list ) {
		$message .= "$pass\n";
	}
	
	open(MAIL, "|/usr/sbin/sendmail -t");
	 
	# Email Header
	print MAIL "To: $to\n";
	print MAIL "From: $from\n";
	print MAIL "Subject: $subject\n\n";
	# Email Body
	print MAIL $message;

	close(MAIL);
	print "Email Sent Successfully to $to\n";
}

sub DoHelp {
    $error = shift;
    switch( $error ) {
        case "ConfigFile" { print "\nERROR: The config file to use was not specified.\n\nUSAGE:\n$0 <-c PATH/CONFIG_FILE.INI> -v <stage|live> | [-h]\n\n"; }
        case "version"    { print "\nERROR: The version (staged or live) to use was not specified.\n\nUSAGE:\n$0 <-c PATH/CONFIG_FILE.INI> -v <stage|live> | [-h]\n\n"; }
        case "ShowHelp"   { print "USAGE:\n$0 <-c PATH/CONFIG_FILE.INI> -v <stage|live> | [-h]\n\n"; }
        else              { print "USAGE:\n$0 <-c PATH/CONFIG_FILE.INI> -v <stage|live> | [-h]\n\n"; }
    }
}
$current_time = `date`;
print "Test complete at $current_time.\n";


