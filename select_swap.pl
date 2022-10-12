#!/usr/bin/perl

use Getopt::Std;
use DBI;
my $dbh = DBI->connect("DBI:mysql:database=rapid_release;host=localhost", "rls", "rls", {'RaiseError' => 0});


# Get the arguments
getopts('t:v:', \%opts);

if ( $opts{'t'} ) {
	$select_date = $opts{'t'};
}
if ( $opts{'v'} ) {
	$vm_name = $opts{'t'};
}

$query = "SELECT sl_vm_name AS VM_NAME, sl_pass_fail AS PASS_FAIL, sl_test_timestamp AS TIMESTAMP FROM swap_log WHERE sl_test_timestamp LIKE \'$select_date%\' AND sl_vm_name like \'$vm_name%\'";

my $sth = $dbh->prepare("$query") ||
  die "Error:" . $dbh->errstr . "\n";
 
$sth->execute ||  die "Error:" . $sth->errstr . "\n";
 
my $names = $sth->{NAME};
my $numFields = $sth->{'NUM_OF_FIELDS'} - 1;

# The output will be HTML, so let's start formatting for that.
print <<EOP;
<html>
<head>
<title>Rapid Release Log Checker</title>
</head>
<body>
<table width=90% border=1>
<tr>
EOP

for my $i ( 0..$numFields ) {
    print "<th>$$names[$i]</th>";
}
print "<tr>\n";
while (my $ref = $sth->fetchrow_arrayref) {
    for my $i ( 0..$numFields ) {
		print "<td align=center border>$$ref[$i]</td>";
    }
    print "</tr>\n";
}

print <<EOP;
</table>
</body>
EOP

$dbh->disconnect;
exit 0;