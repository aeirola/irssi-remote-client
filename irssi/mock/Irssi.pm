package Irssi;
# https://github.com/shabble/irssi-docs/wiki/Irssi
# https://github.com/shabble/irssi-docs/blob/master/Irssi.pod

use threads;
use Data::Dumper;
use Data::GUID;
use IO::Select;
use Irssi::UI::Window;
use Irssi::WindowItem;

# Constants
use base 'Exporter';
use constant (MSGLEVEL_CLIENTCRAP => 0);

# Variables
our (%settings, %windows, @console, $select, %signal_listeners, %input_listeners, %timeouts, @hooks);

our @EXPORT = qw( MSGLEVEL_CLIENTCRAP );
our @EXPORT_OK = qw( %signal_listeners %input_listeners @console);

$select = IO::Select->new();


# Functions
sub print {
	my ($line, $level) = @_;
	push(@console, $line);
	#print("$line\n");
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
	return $sig_name;
}
sub signal_remove {
	my ($tag) = @_;
	delete($signal_listeners{$tag});
}
sub signal_emit {
	my ($sig_name, @params) = @_;
	my $func = $signal_listeners{$sig_name};
	&$func(@params);
}

sub timeout_add_once {
	my ($msecs, $func, $data) = @_;
	my $tag = Data::GUID->new();
	$timeouts{$tag} = $func;
	return $tag;
}
sub timeout_remove {
	my ($tag) = @_;
	delete($timeouts{$tag});
}

sub windows {
	return values(%windows);
}
sub window_find_refnum {
	my ($refnum) = @_;
	return $windows{$refnum};
}

sub INPUT_READ {
	1;
};

package Irssi::Test;

sub handle {
	while(@ready = $select->can_read(0.1)) {
		foreach $fh (@ready) {
			my $listener = $input_listeners{$fh};
			my $func = $listener->{'func'};
			my $data = $listener->{'data'};
			&$func($data);
		}
	}

	fire_hooks();
	fire_timeouts();
}

sub add_hook {
	my ($func) = @_;
	push(@hooks, $func);
}
sub fire_hooks {
	foreach my $func (@hooks) {
		&$func();
	}
	@hooks = ();
}

sub fire_timeouts {
	keys(%timeouts);
	while(my($tag, $func) = each(%timeouts)) {
		&$func();
		delete($timeouts{$tag});
	}
}
sub set_window {
	my $window = Irssi::UI::Window->new(@_);
	$windows{$window->{refnum}} = $window;
}


1;
