use diagnostics;
use warnings;
use strict;

use HTTP::Lite;
require LWP::UserAgent;
use Test::More qw( no_plan );

# Mock some stuff
BEGIN { push @INC,"./mock";}
use Irssi qw( %input_listeners %signal_listeners @console);

# Load script
our ($VERSION, %IRSSI);
require_ok('irssi-rest-api.pl');

# Test static fields
like($VERSION, qr/^\d+\.\d+$/, 'Version format is correct');
like($IRSSI{name}, qr/^irssi .* api$/, 'Contains name');
like($IRSSI{authors}, qr/^.*Axel.*$/, 'Contains author');
like($IRSSI{contact}, qr/^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,4}$/, 'Correctly formatted email');
like($console[-1], qr/10000/, 'Loading line written');

# Check existence of listeners
is(scalar(keys(%input_listeners)), 1, 'Socket input listener set up');
ok(exists($signal_listeners{'print text'}), 'Print signal listener set up');

# Check HTTP interface
my $ua = LWP::UserAgent->new;
is($ua->get('http://localhost:10000/')->code, '401', 'Unauthorized request');

# Close
ok(UNLOAD(), 'Script unloading succeeds');
is(scalar(keys(%input_listeners)), 0, 'Socket input listener cleaned up');

# Write log
print("Console output: \n");
for (my $i = 0; $i < scalar(@console); $i++) {
	print($console[$i]."\n");
}

