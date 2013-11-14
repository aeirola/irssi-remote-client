package Irssi;

# Constants
use base 'Exporter';
use constant (MSGLEVEL_CLIENTCRAP => 0);
our @EXPORT = qw( MSGLEVEL_CLIENTCRAP );

# Functions
sub print {}
sub settings_add_int {}
sub settings_add_str {}
sub settings_get_int {}
sub settings_get_str {}

sub INPUT_READ {}
sub input_add {}
sub signal_add_last {}
sub signal_add_first {}

1;