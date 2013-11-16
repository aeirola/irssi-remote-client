package Irssi;

# Constants
use base 'Exporter';
use constant (MSGLEVEL_CLIENTCRAP => 0);

# Variables
our (%settings, @console);

our @EXPORT = qw( MSGLEVEL_CLIENTCRAP );
our @EXPORT_OK = qw( %signal_listeners %input_listeners @console);

# Functions
sub print {
	my ($line) = @_;
	push @console, $line;
}

sub settings_add_int {
	my ($namespace, $key, $value) = @_;
	$settings{$key} = $value;
}
sub settings_add_str {
	my ($namespace, $key, $value) = @_;
	$settings{$key} = $value;
}
sub settings_get_int {
	my ($key) = @_;
	return $settings{$key};
}
sub settings_get_str {
	my ($key) = @_;
	return $settings{$key};
}

sub input_add {
	my ($fileno, $mode, $handler) = @_;
	print $fileno;
	$input_listeners{$fileno} = $handler;
	return $fileno;
}
sub input_remove {
	my ($fileno) = @_;
	delete $input_listeners{$fileno};
}

sub signal_add_last {
	my ($signal, $function) = @_;
	$signal_listeners{$signal} = $function;
}
sub trigger_signal {
	my $signal = shift;
	my $handler = $signal_listeners{$signal};
	&handler();
}

sub windows {}
sub window_find_refnum {}

sub INPUT_READ {};

1;
