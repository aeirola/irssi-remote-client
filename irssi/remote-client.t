use diagnostics;
use warnings;
use strict;
use utf8;

use threads;
use Test::More;

use Data::Dumper; # dbug prints
use LWP::UserAgent;
use JSON;
use Digest::SHA qw(sha512_base64);
use Encode;

# Mock some stuff
use lib './mock';
use Irssi qw( %input_listeners %signal_listeners @console);

# Load script
our ($VERSION, %IRSSI);
require_ok('remote-client.pl');

my $port = 47895;
my $password = 'test_password';
Irssi::settings_set_int('remote_client_port', $port);
Irssi::settings_set_str('remote_client_password', $password);
Irssi::settings_set_int('remote_client_log_level', 0);


# Test static fields
like($VERSION, qr/^\d+\.\d+$/, 'Version format is correct');
like($IRSSI{name}, qr/^Irssi .*remote.*$/, 'Contains name');
like($IRSSI{authors}, qr/^.*Axel.*$/, 'Contains author');
like($IRSSI{contact}, qr/^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,4}$/, 'Correctly formatted email');
like($console[-1], qr/$port/, 'Loading line written');
isnt(Irssi::settings_get_str('remote_client_password'), undef, 'Password setting added');
isnt(Irssi::settings_get_int('remote_client_port'), undef, 'Port setting added');

# Check existence of listeners
is(scalar(keys(%input_listeners)), 1, 'Socket input listener set up');
is(scalar(keys(%signal_listeners)), 2, 'Print and settings signal listener set up');


# Check HTTP interface
my $ua = LWP::UserAgent->new('keep_alive' => 1);
my $base_url = "http://localhost:$port";
is_response('code' => 401, 'test_name' => 'Unauthorized request');

$ua->default_header('Irssi-Authorization' => sha512_base64($password));
is_response('code' => 404, 'test_name' => 'Invalid path');

Irssi::settings_set_str('remote_client_password', 'invalid_password');
is_response('code' => 401, 'test_name' => 'Unauthorized request');
Irssi::settings_set_str('remote_client_password', $password);

# Test CORS settings
is_response('method' => 'OPTIONS', 'test_name' => 'CORS disabled', expected_headers => {
	'Access-Control-Allow-Origin' => undef,
	'Access-Control-Allow-Methods' => undef,
	'Access-Control-Allow-Headers' => undef,
	'Access-Control-Max-Age' => undef});
Irssi::settings_set_bool('remote_client_allow_cors', 1);
is_response('method' => 'OPTIONS', 'test_name' => 'CORS enabled', expected_headers => {
	'Access-Control-Allow-Origin' => '*',
	'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS',
	'Access-Control-Allow-Headers' => 'Irssi-Authorization, Content-Type',
	'Access-Control-Max-Age' => '1728000'});
Irssi::settings_set_bool('remote_client_allow_cors', 0);

# Check JSON RPC interface
is_jrpc('method' => 'getWindows', 'result' => []);
is_jrpc('method' => 'getWindow', 'params' => {'undefinedParam' => 'hello'}, 'error' => -32603);
is_jrpc('method' => 'undefinedMethod', 'error' => -32603);
is_response('url' => '/json-rpc', 'method' => 'POST', 'code' => 500, 'test_name' => 'Missing JSON');
is_response('url' => '/json-rpc', 'method' => 'POST',
			'body' => '{"jsonrpc": "2.0", "method": "foobar, "params": "bar", "baz]', 'code' => 500,
			'test_name' => 'Invalid JSON');
is_response('url' => '/json-rpc', 'method' => 'POST',
			'body' => '{"jsonrpc": "2.0", "method": 1, "params": "bar"}', 'code' => 500,
			'test_name' => 'Invalid request');
is_response('url' => '/json-rpc', 'method' => 'POST', 'body' => '[]',
			'code' => 500, 'test_name' => 'Invalid batch');
# GET api
is_response('url' => '/json-rpc?method=getWindows', 'data' => '{"version":"1.1","result":[]}',
			'test_name' => 'GET request');


# Set data
Irssi::Test::set_window('refnum' => 1, 'type' => undef, 'name' => '(status)');
Irssi::Test::set_window('refnum' => 2, 'type' => 'CHANNEL', 'name' => '#channel',
						'topic' => 'Something interesting', 'nicks' => ['nick1', 'nick2'],
						'lines' => [[1, 'line1'], [2, 'line2']]);
Irssi::Test::set_window('refnum' => 3, 'type' => 'CHANNEL', 'name' => '#fast_channel',
						'topic' => 'Something fast', 'nicks' => ['nick1', 'nick2'],
						'lines' => [[1386447100, 'line1'],
									[1386447200, 'line2'], [1386447200, 'line3'], [1386447200, 'line4'],
									[1386447300, 'line5'], [1386447300, 'line6']]);
# getWindows
is_jrpc('method' => 'getWindows', 'result' => [{
		'refnum' => 1,
		'type' => 'EMPTY',
		'name' => '(status)'
	},{
		'refnum' => 3,
		'type' => 'CHANNEL',
		'name' => '#fast_channel'
	},{
		'refnum' => 2,
		'type' => 'CHANNEL',
		'name' => '#channel'
	}]);

Irssi::Test::set_window('refnum' => 4, 'type' => 'CHANNEL', 'name' => '#non_ascii_channel',
						'topic' => 'Something non-ascii åäö', 'nicks' => ['nick1'],
						'lines' => [[1, Encode::encode('utf8', 'åäö')]]);

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
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 4}, 'result' => [
	{'timestamp' => 1, 'text' => 'åäö'}]);
# Limits
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 2, 'timestampLimit' => 1},
		'result' => [{'timestamp' => 2, 'text' => 'line2'}]);
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 2, 'timestampLimit' => 2}, 'result' => []);
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 2, 'timestampLimit' => 10}, 'result' => []);
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 2, 'rowLimit' => 1},
		'result' => [{'timestamp' => 2, 'text' => 'line2'}]);

# Subsecond timestamps
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 3, 'timestampLimit' => 1386447200.000},
		'result' => [{'timestamp' => 1386447200.001, 'text' => 'line3'},
					 {'timestamp' => 1386447200.002, 'text' => 'line4'},
					 {'timestamp' => 1386447300.000, 'text' => 'line5'},
					 {'timestamp' => 1386447300.001, 'text' => 'line6'}]);
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 3, 'rowLimit' => 3},
		'result' => [{'timestamp' => 1386447200.002, 'text' => 'line4'},
					 {'timestamp' => 1386447300.000, 'text' => 'line5'},
					 {'timestamp' => 1386447300.001, 'text' => 'line6'}]);
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 3, 'rowLimit' => 3, 'timestampLimit' => 1386447200.000},
		'result' => [{'timestamp' => 1386447200.002, 'text' => 'line4'},
					 {'timestamp' => 1386447300.000, 'text' => 'line5'},
					 {'timestamp' => 1386447300.001, 'text' => 'line6'}]);
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 3, 'rowLimit' => 100, 'timestampLimit' => 1386447300.000},
		'result' => [{'timestamp' => 1386447300.001, 'text' => 'line6'}]);
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 3, 'rowLimit' => 100, 'timestampLimit' => 1386447300.001},
		'result' => []);
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 3, 'timestampLimit' => 1386447200.001},
		'result' => [{'timestamp' => 1386447200.002, 'text' => 'line4'},
					 {'timestamp' => 1386447300.000, 'text' => 'line5'},
					 {'timestamp' => 1386447300.001, 'text' => 'line6'}]);
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 3, 'timestampLimit' => 1386447250},
		'result' => [{'timestamp' => 1386447300.000, 'text' => 'line5'},
					 {'timestamp' => 1386447300.001, 'text' => 'line6'}]);



# Timeouts
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 2, 'timestampLimit' => 1, 'timeout' => 1000},
		'result' => [{'timestamp' => 2, 'text' => 'line2'}]);
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 2, 'timestampLimit' => 2, 'timeout' => 100},
		'result' => []);
Irssi::Test::add_hook(sub {Irssi::window_find_refnum(2)->print('hi')});
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 2, 'timestampLimit' => 2, 'timeout' => 100},
		'result' => [{'timestamp' => 3, 'text' => 'hi'}]);
is_jrpc('method' => 'getWindowLines', 'params' => {'refnum' => 404}, 'result' => []);

# sendMessage
is_jrpc('method' => 'sendMessage', 'params' => {'refnum' => 2, 'message' => 'hello'});
is_commands('refnum' => 2, 'commands' => ['msg * hello']);
is_jrpc('method' => 'sendMessage', 'params' => {'refnum' => 2, 'message' => ''});
is_commands('refnum' => 2, 'commands' => []);
is_jrpc('method' => 'sendMessage', 'params' => {'refnum' => 2, 'message' => 'åäö'});
is_commands('refnum' => 2, 'commands' => ['msg * åäö']);


# Test unloading
ok(UNLOAD(), 'Script unloading succeeds');
is(scalar(keys(%input_listeners)), 0, 'Socket input listener cleaned up');

done_testing();

# Write log
print("Console output: \n");
for (my $i = 0; $i < scalar(@console); $i++) {
	#print($console[$i]."\n");
}

# Helpers
sub is_jrpc {
	my %args = @_;
	my $method = $args{method};
	my $params = $args{params} || {};
	my $result = $args{result};
	my $error = $args{error};
	my $test_name = "$method (" . JSON::encode_json($params). ")" ;
	my $id =  $args{id} || 1;

	my $request = {'jsonrpc' => '2.0', 'method' => $method, 'id' => $id};
	if ($params) {
		$request->{params} = $params;
	}
	my $thread = async {$ua->post($base_url . '/json-rpc', 'Content' => JSON::encode_json($request))};
	Irssi::Test::handle();
	my $response = $thread->join();

	my $content = JSON::decode_json($response->content);
	#print(Dumper($content));
	if ($error) {
		is($content->{error}->{code}, $error, $test_name . ' (errors)');
		is($content->{result}, undef, $test_name . ' (data)');
	} else {
		is($content->{error}, undef, $test_name . ' (errors)');
		is_deeply($content->{result}, $result, $test_name . ' (data)');
	}
}

sub is_response {
	my %args = @_;
	my $method = $args{method} || 'GET';
	my $url = $args{url} || '/';
	my $body = $args{body};
	my $expected_code = $args{code} || '200';
	my $expected_headers = $args{expected_headers} || {};
	my $expected_data = $args{data} || '';
	my $test_name = $args{test_name} || "$method $url";

	my $thread;
	$thread = async {
		my $h = HTTP::Headers->new();
		my $request = HTTP::Request->new($method, $base_url . $url, $h, $body);
		$ua->request($request);
	};

	Irssi::Test::handle();
	my $response = $thread->join();
	is($response->code, $expected_code, $test_name. ' (code)');
	my $data = $response->content;
	is($data, $expected_data, $test_name. ' (data)');

	keys %$expected_headers;
	while(my($k, $v) = each %$expected_headers) {
		is($response->header($k), $v, $test_name. " (header $k)");
	}
}

sub is_commands {
	my %args = @_;
	my $refnum = $args{refnum};
	my @commands = $args{commands};

	my $window = Irssi::window_find_refnum($refnum);
	my $window_item = $window->{active};

	is_deeply($window_item->{_commands}, @commands, 'Check commands');
	$window_item->{_commands} = [];
}
