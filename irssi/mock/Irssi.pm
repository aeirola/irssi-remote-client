package Irssi;

use threads;
use threads::shared;
use IO::Select;
use Data::Dumper; # dbug prints

# Constants
use base 'Exporter';
use constant (MSGLEVEL_CLIENTCRAP => 0);

# Variables
our (%settings, @console, $thread, $select);

our @EXPORT = qw( MSGLEVEL_CLIENTCRAP );
our @EXPORT_OK = qw( %signal_listeners %input_listeners @console);


$select = IO::Select->new($source);


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

sub _handle_input {
	while(1) {
		@ready = $select->can_read(1);
		unless (scalar(keys(%input_listeners))) {
			return;
		}
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
	if (!defined($thread) and (threads->tid() == 0)) {
		$thread = threads->create('_handle_input');
	}
	return $source;
}

sub input_remove {
	my ($tag) = @_;
	$select->remove($tag);
	delete($input_listeners{$tag});
	if (scalar(keys(%input_listener)) == 0 && defined($thread)) {
		#$thread->join();
	}
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

sub windows {}
sub window_find_refnum {}

sub INPUT_READ {
	1;
};

1;
