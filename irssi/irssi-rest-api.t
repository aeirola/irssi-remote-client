use diagnostics;
use warnings;
use strict;

use Test::More qw( no_plan );

# Mock some stuff
BEGIN { push @INC,"./mock";}
our ($VERSION, %IRSSI);

# Load script
require_ok('irssi-rest-api.pl');

# Test simple things
like($VERSION, qr/^\d+\.\d+$/, 'Version format is correct');
