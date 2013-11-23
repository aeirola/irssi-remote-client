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
my $ua = LWP::UserAgent->new('keep_alive' => 1);
my $base_url = 'http://localhost:10000';
is_response('url' => '/', 'code' => 401, 'test_name' => 'Unauthorized request');

$ua->default_header('Secret' => Irssi::settings_get_str('rest_password'));
is_response('url' => '/', 'code' => 404, 'test_name' => 'Invalid path');
is_jrpc('method' => 'getWindows', 'result' => []);

Irssi::_set_window('refnum' => 1, 'type' => undef, 'name' => '(status)');
Irssi::_set_window('refnum' => 2, 'type' => 'CHANNEL', 'name' => '#channel',
					'topic' => 'Something interesting', 'nicks' => ['nick1', 'nick2'],
					'lines' => ['line1', 'line2']);

# getWindows
is_jrpc('method' => 'getWindows', 'result' => [{
 		'refnum' => 1,
 		'type' => 'EMPTY',
 		'name' => '(status)'
 	},{
 		'refnum' => 2,
 		'type' => 'CHANNEL',
 		'name' => '#channel'
 	}]);

# getWindow
is_jrpc('method' => 'getWindow', 'params' => {'refnum' => 1}, 'result' => {
		'refnum' => 1,
		'type' => 'EMPTY',
		'name' => '(status)',
		'lines' => []
	});
is_jrpc('method' => 'getWindow', 'params' => {'refnum' => 2}, 'result' => {
		'refnum' => 2,
		'type' => 'CHANNEL',
		'name' => '#channel',
		'topic' => 'Something interesting',
		'nicks' => ['nick1', 'nick2'],
		'lines' => [{'timestamp' => 1, 'text' => 'line1'}, 
					{'timestamp' => 2, 'text' => 'line2'}]
	});
is_jrpc('method' => 'getWindow', 'params' => {'refnum' => 404}, 'result' => undef);

# getWindowLines
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 2}, 'result' => [
	{'timestamp' => 1, 'text' => 'line1'},
	{'timestamp' => 2, 'text' => 'line2'}]);
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 404}, 'result' => []);

# sendMessage
is_jrpc('method' => 'sendMessage', 'params' => {'refnum' => 2, 'message' => 'hello'}, 'result' => []);



# Close
ok(UNLOAD(), 'Script unloading succeeds');
is(scalar(keys(%input_listeners)), 0, 'Socket input listener cleaned up');

# Write log
print("Console output: \n");
for (my $i = 0; $i < scalar(@console); $i++) {
	print($console[$i]."\n");
}

# Helpers
sub is_jrpc {
	my %args = @_;
	my $method = $args{method};
	my $params = $args{params};
	my $result = $args{result};
	my $test_name = $method;
	my $id =  $args{id} || 1;

	my $request = {'jsonrpc' => '2.0', 'method' => $method, 'id' => $id};
	if ($params) {
		$request->{params} = $params;
	}
	my $thread = async {$ua->post($base_url . '/rpc', 'Content' => JSON::encode_json($request))};
	Irssi->_handle();
	my $response = $thread->join();

	my $content = JSON::decode_json($response->content);
	is($content->{error}, undef);
	is_deeply($content->{result}, $result, $test_name);
}

sub is_response {
	my %args = @_;
	my $method = $args{method} || 'GET';
	my $url = $args{url};
	my $body = $args{body};
	my $expected_code = $args{code} || '200';
	my $expected_data = $args{data} || '';
	my $test_name = $args{test_name} || "$method $url";

	my $thread;
	if ($method eq 'GET') {
		$thread = async {$ua->get($base_url . $url)};
	} elsif ($method eq 'POST') {
		$thread = async {$ua->post($base_url . $url, 'Content' => $body)};
	}

	Irssi->_handle();
	my $response = $thread->join();
	is($response->code, $expected_code, $test_name. ' (code)');
	my $data = $response->content;
	is($data, $expected_data, $test_name. ' (data)');
}
