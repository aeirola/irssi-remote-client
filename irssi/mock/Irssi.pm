package Irssi;
# https://github.com/shabble/irssi-docs/wiki/Irssi
# https://github.com/shabble/irssi-docs/blob/master/Irssi.pod

use Data::Dumper;
use IO::Select;
use Irssi::UI::Window;
use Irssi::WindowItem;

# Constants
use base 'Exporter';
use constant (MSGLEVEL_CLIENTCRAP => 0);

# Variables
our (%settings, %windows, @console, $select, %signal_listeners, %input_listeners);

our @EXPORT = qw( MSGLEVEL_CLIENTCRAP );
our @EXPORT_OK = qw( %signal_listeners %input_listeners @console);

$select = IO::Select->new();


# Functions
sub print {
	my ($line, $level) = @_;
	push(@console, $line);
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

sub _handle {
	while(@ready = $select->can_read(0.1)) {
		foreach $fh (@ready) {
			my $listener = $input_listeners{$fh};
			my $func = $listener->{'func'};
			my $data = $listener->{'data'};
			&$func($data);
		}
	}
}

sub input_add {
	my ($source, $condition, $func, $data) = @_;
	$select->add($source);
	$input_listeners{$source} = {'func' => $func, 'data' => $data};
	return $source;
}

sub input_remove {
	my ($tag) = @_;
	$select->remove($tag);
	delete($input_listeners{$tag});
}

sub signal_add_last {
	my ($sig_name, $func) = @_;
	$signal_listeners{$sig_name} = $func;
}
sub trigger_signal {
	my ($sig_name) = @_;
	my $func = $signal_listeners{$sig_name};
	&func();
}

sub windows {
	return values(%windows);
}
sub window_find_refnum {
	my ($refnum) = @_;
	return $windows{$refnum};
}
sub _set_window {
	my $window = Irssi::UI::Window->new(@_);
	$windows{$window->{refnum}} = $window;
}


sub INPUT_READ {
	1;
};

1;
