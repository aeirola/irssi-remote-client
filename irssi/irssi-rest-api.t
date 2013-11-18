use diagnostics;
use warnings;
use strict;

use threads;
use Data::Dumper; # dbug prints
use LWP::UserAgent;
use JSON;
use Test::More qw( no_plan );

# Mock some stuff
BEGIN { push @INC,"./mock";}
use Irssi qw( %input_listeners %signal_listeners @console);
use Irssi::Window;
use Irssi::WindowItem;

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
my $base_url = 'http://localhost:10000';
is_response('url' => '/', 'code' => 401, 'test_name' => 'Unauthorized request');

$ua->default_header('Secret' => Irssi::settings_get_str('rest_password'));
is_response('url' => '/', 'test_name' => 'Authorized request');
is_response('url' => '/windows', 'data' => [], 'test_name' => 'Get empty windows');

Irssi::set_window(Irssi::Window->new(1, '(status)'));
Irssi::set_window(Irssi::Window->new(2, '#channel'));
is_response('url' => '/windows', 'test_name' => 'Get windows', 'data' => [{
		'refnum' => 1,
		'type' => 'EMPTY',
		'name' => '(status)',
		'topic' => undef
	},{
		'refnum' => 2,
		'type' => 'EMPTY',
		'name' => '#channel',
		'topic' => undef
	}]);
is_response('url' => '/windows/1', 'test_name' => 'Get window data', 'data' => {
		'refnum' => 1,
		'type' => 'EMPTY',
		'name' => '(status)',
		'topic' => undef,
		'lines' => []
	});
is_response('url' => '/windows/asdfasdf', 'test_name' => 'Get nonexistent window data');
is_response('url' => '/windows/1/lines', 'test_name' => 'Get window lines', 'data' => []);



# Close
ok(UNLOAD(), 'Script unloading succeeds');
is(scalar(keys(%input_listeners)), 0, 'Socket input listener cleaned up');

# Write log
print("Console output: \n");
for (my $i = 0; $i < scalar(@console); $i++) {
	print($console[$i]."\n");
}

# Helpers
sub is_response {
	my %args = @_;
	my $url = $args{'url'};
	my $expected_code = $args{'code'} || '200';
	my $expected_data = $args{'data'};
	my $test_name = $args{'test_name'} || '';

	my $thread = async {$ua->get($base_url . $url)};
	Irssi->_handle();
	my $response = $thread->join();
	is($response->code, $expected_code, $test_name. ' (code)');
	my $data = undef;
	if ($response->content ne "\n") {
		$data = JSON::decode_json($response->content);
	}
	is_deeply($data, $expected_data, $test_name. ' (data)');
}
