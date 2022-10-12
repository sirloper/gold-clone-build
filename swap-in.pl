#!/usr/bin/perl

# Initialize
use Getopt::Std;
use Config::IniFiles;
use threads;
use threads::shared;
use Switch;

# Prepare MySQL connection
use DBI;
my $dbh = DBI->connect("DBI:mysql:database=rapid_release;host=localhost", "rls", "rls", {'RaiseError' => 0});

# Get the arguments
getopts('c:uph', \%opts);

# Command-line checking
if ( $opts{'h'} ) {
	DoHelp( "ShowHelp" );
	exit( 0 );
}
unless( $opts{'c'} ) {
	DoHelp( "ConfigFile" );
	exit( 2 );
}
if ( ( $opts{'u'} ) || ( $opts{'p'} ) ) {
	print "\n\nIncorrect usage!  Did you mean to call clone.pl instead?\n\n\n";
	exit( 1 );
}

tie %cfg, 'Config::IniFiles', ( -file => "$opts{'c'}" );


print "\nPreparing to swap in all targets defined in configuration file \"$opts{'c'}\".\n\nPlease wait, this may take a while..\n\n";

# Log this swap run with a header
$current_date = `date +%Y-%m-%d`;
$current_time = `date +%I:%M:%S`;
chomp( $current_date, $current_time );
open( TEST_LOG, ">>", "logs/swap-clones.log" ) or warn( "Could not open swap-clones.log for writing: $!\n" );
print TEST_LOG "=================================================================================\n";
print TEST_LOG "INFO: Beginning swapping of clones at $current_date $current_time contained in $opts{'c'}\n";
close( TEST_LOG );
foreach $current_target ( keys %cfg ) {
	print "Re-configuring $current_target\n";
	$liveipaddr = $cfg{$current_target}{'liveipaddr'};
	$ipaddr = $cfg{$current_target}{'ipaddr'};
	$netmask = $cfg{$current_target}{'netmask'};
	$gateway = $cfg{$current_target}{'default_gateway'};
	$hostname = lc( $current_target );

	open( IFCFG_ETH0, ">", "/tmp/ifcfg-ens32-$current_target" );
	select IFCFG_ETH0;
	write;
	select STDOUT;
	close( IFCFG_ETH0 );
	
	open( NETWORK_FILE, ">", "/tmp/network-$current_target" );
	select NETWORK_FILE;
	write;
	select STDOUT;
	close( NETWORK_FILE );
	
	open( ETC_HOSTS, ">", "/tmp/hosts-$current_target" );
	select ETC_HOSTS;
	write;
	select STDOUT;
	close( ETC_HOSTS );
	
	# Halt the outgoing machine, SCP the new file and reboot the incomming machine
	system( "scp -oConnectTimeout=3 -oStrictHostKeyChecking=no /tmp/ifcfg-ens32-$current_target root\@$ipaddr:/etc/sysconfig/network-scripts/ifcfg-ens32 2> /dev/null" );
	if ( $? ) {
		$pass_fail = "FAIL";
		print "Not doing swap in.  Staged target does not seem to exist for $current_target!\n";
		print "\nDone with swap in of $current_target.\n\n";
		open( TEST_LOG, ">>", "logs/swap-clones.log" ) or warn( "Could not open swap-clones.log for writing: $!\n" );
		print TEST_LOG "ERROR: Swap of $current_target not attempted - no staged clone!\n";
		close( TEST_LOG );
	} else {
		$pass_fail = "PASS";
		system( "ssh -oConnectTimeout=3  -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no root\@$liveipaddr 'halt -p; exit' 2> /dev/null" );
		system( "scp -oConnectTimeout=3  -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no /tmp/hosts-$current_target root\@$ipaddr:/etc/hosts 2> /dev/null" );
		system( "ssh -oConnectTimeout=3  -oGSSAPIAuthentication=no -oStrictHostKeyChecking=no root\@$ipaddr 'reboot; exit' 2> /dev/null" );
		open( TEST_LOG, ">>", "logs/swap-clones.log" ) or warn( "Could not open swap-clones.log for writing: $!\n" );
		print TEST_LOG "INFO: Swap of $current_target completed successfully.\n";
		close( TEST_LOG );
	}
	
	# Log this swap to MySQL
	my $query = sprintf("INSERT INTO swap_log ( sl_vm_name, sl_pass_fail, sl_test_timestamp ) VALUES (%s, %s, %s )",
                    $dbh->quote("$current_target"), $dbh->quote("$pass_fail"), $dbh->quote("$current_date $current_time") );
	$dbh->do($query);

}

# Disconnect from MySQL
$dbh->disconnect();

# Log ending of the swap
$current_date = `date +%Y-%m-%d`;
$current_time = `date +%I:%M:%S`;
chomp( $current_date, $current_time );
chomp( $current_date );
open( TEST_LOG, ">>", "logs/swap-clones.log" ) or warn( "Could not open swap-clones.log for writing: $!\n" );
print TEST_LOG "INFO: Ending swapping of clones at $current_date $current_time\n";
print TEST_LOG "=================================================================================\n";
close( TEST_LOG );

$current_date = `date`;

print "Swap is complete at $current_date.  Please allow 5-10 minutes for clones to reboot.\n\n";

sub DoHelp {
	my $error = shift;
	switch( $error ) {
		case "ConfigFile" { print "\nERROR: The config file to use was not specified.\n\nUSAGE:\n$0 <-c PATH/CONFIG_FILE.INI> | [-h]\n\n"; }
		case "ShowHelp"   { print "USAGE:\n$0 <-c PATH/CONFIG_FILE.INI>[-h]\n\n"; }
		else              { print "USAGE:\n$0 <-c PATH/CONFIG_FILE.INI> | [-h]\n\n"; }
	}
}


# Format Definitions
format ETC_HOSTS =
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
@*			@* @*.ihtech.com
$liveipaddr, $hostname, $hostname
.

format IFCFG_ETH0 =
DEVICE=ens32
TYPE=Ethernet
ONBOOT=yes
NM_CONTROLLED=no
BOOTPROTO=static
IPADDR=@*
$liveipaddr
NETMASK=@*
$netmask
GATEWAY=@*
$gateway
.

format NETWORK_FILE =
NETWORKING=yes
HOSTNAME=@*
        $hostname
DNS1=10.32.65.11
DNS2=10.32.65.12
DOMAIN="ihtech.com ihealthtechnologies.com"
GATEWAY=@*
$gateway
.

format HOSTS_FILE =
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
@*	@*	@*.ihtech.com
$liveipaddr,	$hostname, $hostname
.

__END__

