use diagnostics;
use warnings;
use strict;

use Test::More qw( no_plan );

# Mock some stuff
BEGIN { push @INC,"./mock";}
use Irssi qw( %input_listeners %signal_listeners );

# Load script
our ($VERSION, %IRSSI);
require_ok('irssi-rest-api.pl');

# Test static fields
like($VERSION, qr/^\d+\.\d+$/, 'Version format is correct');
like($IRSSI{name}, qr/^irssi .* api$/, 'Contains name');
like($IRSSI{authors}, qr/^.*Axel.*$/, 'Contains author');
like($IRSSI{contact}, qr/^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,4}$/, 'Correctly formatted email');

# Check existence of listeners
is(scalar keys %input_listeners, 1, 'Input listener set up');
ok(exists $signal_listeners{'print text'}, 'Print listener set up');


# Close
UNLOAD();
is(scalar keys %input_listeners, 0, 'Input listener cleaned up');
