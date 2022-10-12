#!/usr/bin/perl

# Initialize
use Getopt::Std;
use Config::IniFiles;
use threads;
use threads::shared;
use Switch;
use DBI;
use Term::ReadKey;

# Get the arguments
getopts('c:u:p:h', \%opts);

# Check arguments
if ( $opts{'h'} ) {
	DoHelp( "ShowHelp" );
	exit( 0 );
}
unless( $opts{'c'} ) {
	DoHelp( "ConfigFile" );
	exit( 2 );
}
unless( $opts{'u'} ) {
	DoHelp( "UserPass" );
	exit( 3 );
}
my $username = $opts{'u'};
if ( $opts{'p'} ) {
	$password = $opts{'p'};
} else {
	ReadPass();
}

my $timestamp = localtime( time );
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
$year += 1900;
$mon += 1;
my $datestamp = sprintf("%04d%02d%02d%02d%02d", $year, $mon, $mday, $hour, $min);

my %cfg;
my @threads;

tie %cfg, 'Config::IniFiles', ( -file => "$opts{'c'}" );

print "\nPreparing to clone all targets defined in configuration file \"$opts{'c'}\".\n\nPlease wait, this will take a while..\n\n";
foreach $current_target ( keys %cfg ) {
	my $t = threads->new( \&SpawnClone, $current_target );
    push( @threads, $t );
}

foreach ( @threads ) {
	my $current_target = $_->join;
	print "\nDone with clone of $current_target.\nLog info can be found at logs/$current_target\_$datestamp.log\n";
}


sub ReadPass {
        print "Passord for \"$username\": ";
        ReadMode( 'noecho' );
        $password = <STDIN>;
        chomp $password;
        ReadMode( 0 );
        print "\n\n";
}

sub SpawnClone {
	# initialize MySQL for this thread ONLY
	my $dbh = DBI->connect("DBI:mysql:database=rapid_release;host=localhost", "rls", "rls", {'RaiseError' => 0});
	#$current_date = `date +%Y-%m-%d`;
	#$current_time = `date +%I:%M:%S`;
	#chomp( $current_date, $current_time );
	
	my $current_target = shift;
	open( LOG, ">>", "logs/$current_target\_$datestamp.log" );
	print LOG "Process started on ", $timestamp, "\n";
	$template = $cfg{$current_target}{'source'};
	print "Starting clone of $current_target from source $template ...\n";
	$datastore = $cfg{$current_target}{'datastore'};
	$vmhost = $cfg{$current_target}{'vmhost'};
	$ipaddr = $cfg{$current_target}{'ipaddr'};
	$netmask = $cfg{$current_target}{'netmask'};
	$network = $cfg{$current_target}{'network'};
	$gateway = $cfg{$current_target}{'default_gateway'};
	$memory = $cfg{$current_target}{'memory'};
	$disksize = $cfg{$current_target}{'disksize'};
	$cpus = $cfg{$current_target}{'cpus'};
	$shares = $cfg{$current_target}{'shares'};
	$hostname = $cfg{$current_target}{'vcenter'};
	$targetvm = $current_target;
	$datacenter = $cfg{$current_target}{'datacenter'};
	$log_cmd = qq|Command Run:\nansible-playbook -e "hostname=$hostname datacenter=$datacenter esxi_hostname=$vmhost cpus=$cpus memory=$memory template=$template targetvm=$targetvm\_$datestamp datastore=$datastore username=$username shares=$shares gateway=$gateway ipaddr=$ipaddr netmask=$netmask network=$network password=$password" ansible-clone.yml\n|;
	print LOG $log_cmd;
	close( LOG );
	# The following needs to be all on the same line to preserve santity.  I know. It sucks.
	$output = `ansible-playbook -e "hostname=$hostname datacenter=$datacenter esxi_hostname=$vmhost cpus=$cpus memory=$memory template=$template targetvm=$targetvm\_$datestamp datastore=$datastore username=$username shares=$shares gateway=$gateway ipaddr=$ipaddr netmask=$netmask network=$network password=$password" ansible-clone.yml`;
	open( LOG, ">>", "logs/$current_target\_$datestamp.log" );
	print LOG $output;
	close( LOG );
	
	# Log this creation event to MySQL
	#my $query = sprintf("INSERT INTO create_log ( cl_vm_name, cl_source_name, cl_cmd_output, cl_create_timestamp ) VALUES (%s, %s, %s, %s )",
        #$dbh->quote("$current_target"), $dbh->quote("$sourcevm"), $dbh->quote("$output"), $dbh->quote("$current_date $current_time") );
	#$dbh->do($query);
	$dbh->disconnect;
	
	return $current_target;
}

sub CreateTemplate {
	my ( $targetvm, $ipaddr, $gateway, $netmask, $memory, $disksize, $cpus, $network ) = @_;
	open( XML_SPEC, ">", "xml/$targetvm\_$datestamp.xml" );
	select( XML_SPEC );
	write;
	select( STDOUT );
	close( XML_SPEC );
	1;
}

sub DoHelp {
	my $error = shift;
	switch( $error ) {
		case "ConfigFile" { print "\nERROR: The config file to use was not specified.\n\nUSAGE:\n$0 <-c CONFIG_FILE.INI> <-u USERNAME> [-p PASSWORD] | [-h]\n\n" }
		case "UserPass"   { print "\nERROR: The user name was not specified.\n\nUSAGE:\n$0 <-c CONFIG_FILE.INI> <-u USERNAME> [-p PASSWORD] | [-h]\n\n" }
		case "ShowHelp"   { print "USAGE:\n$0 <-c CONFIG_FILE.INI> <-u USERNAME> [-p PASSWORD] | [-h]\n\n" }
		else              { print "USAGE:\n$0 <-c CONFIG_FILE.INI> <-u USERNAME> [-p PASSWORD] | [-h]\n\n" }
	}
}
	
# Formats
format XML_SPEC =
<?xml version="1.0"?>
<Specification>
   <Customization-Spec>
          <Domain>ihtech.com</Domain>
          <IP>@*</IP>
		      $ipaddr
          <Gateway>@*</Gateway>
		           $gateway
          <Netmask>@*</Netmask>
		           $netmask
   </Customization-Spec>
 <Virtual-Machine-Spec>
      <Memory>@*</Memory>
	          $memory
      <Disksize>@*</Disksize>
	            $disksize
      <Number-of-CPUS>@*</Number-of-CPUS>
	                  $cpus
      <Network>@*</Network>
	           $network
  </Virtual-Machine-Spec>
</Specification>
.
	

print "\nAll clones complete.\n";
__END__

=pod

=head1 clone.pl - script to clone multiple VMs at once.

=head2 EXAMPLE:

=begin text

	clone.pl -c CONFIGURATION_FILE -u DOMAIN\USERNAME <-p PASSWORD>
	clone.pl -h

=end text

=head2 CONFIGURATION FILE FORMAT:

=begin text

	[CLONE_TEST_TARGET]
	source=CLONE_TEST
	datastore=DT2-L079-RHEL
	vmhost=uapesx15c.ihtech.com
	network=NET-10.32.2.0_23-ATL-DEV-SRVR
	netmask=255.255.255.0
	default_gateway=10.32.2.1
	ipaddr=10.10.10.11
	memory=1024
	disksize=10240
	cpus=1

	[CLONE_TEST_TARGET2]
	source=CLONE_TEST
	datastore=DT2-L079-RHEL
	vmhost=uapesx15c.ihtech.com
	network=NET-10.32.2.0_23-ATL-DEV-SRVR
	netmask=255.255.255.0
	default_gateway=10.32.2.1
	ipaddr=10.10.10.12
	memory=1024
	disksize=10240
	cpus=1

=end text

=cut

