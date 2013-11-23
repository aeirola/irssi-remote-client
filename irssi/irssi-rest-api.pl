# irssi-client-api.pl -- enables remote control of irssi
use strict;
use Irssi;          # Interfacing with irssi
use Irssi::TextUI;  # Enable access to scrollback history, Irssi::UI::Window->view is defined here!

use Try::Tiny;      # try {} catch {}; structure
use HTTP::Daemon;   # HTTP connections
use HTTP::Status;   # HTTP Status codes
use HTTP::Response; # HTTP Responses

use JSON::RPC::Common::Marshal::HTTP;   # JSON-RPC handling
use Protocol::WebSocket;                # Websocket connection handling

our $VERSION = '0.01';
our %IRSSI = (
	authors     => 'Axel Eirola',
	contact     => 'axel.eirola@iki.fi',
	name        => 'irssi rest api',
	description => 'This script allows ' .
				   'remote clients to  ' .
				   'control irssi via REST API',
	license     => 'Public Domain',
);

our $server = undef;        # Stores the server information
our %connections = ();      # Stores client connections information
our $commander = Irssi::JSON::RPC::Commander->new();
our $marshaller = JSON::RPC::Common::Marshal::HTTP->new();


##
#   Entry points
##
sub LOAD {
	# Called at end of script
	Irssi::settings_add_int('rest', 'rest_port', 10000);
	Irssi::settings_add_str('rest', 'rest_password', 'd0ntLe@veM3');
	Irssi::settings_add_str('rest', 'rest_log_level', 'INFO');
	setup_tcp_socket();

	Irssi::signal_add_last('print text', 'print_text_event');
}

sub UNLOAD {
	# Called by Irssi on unload
	destroy_sockets();
}

sub RELOAD {
	# TODO: Add signal listener for settings change
	destroy_sockets();
	setup_tcp_socket();
}



##
#   Command handling
##

{
	package Irssi::JSON::RPC::Commander;

	sub new {
		return bless {}, shift;
	}

	sub getWindows {
		my ($self) = @_;
		my @windows = ();
		foreach my $window (Irssi::windows()) {
			my $item = $window->{active};
			my %window_data = (
				'refnum' => $window->{refnum},
				'type' => $item->{type} || 'EMPTY',
				'name' => $window->get_active_name()
			);
			push(@windows, \%window_data);
		}
		return \@windows;
	}

	sub getWindow {
		my $self = shift;
		my %args = @_;
		my $refnum = $args{refnum} or die 'Missing parameter refnum';

		my $window = Irssi::window_find_refnum($refnum);
		unless ($window) {return undef;};

		my $item = $window->{active};

		my %window_data = (
			'refnum' => $window->{refnum},
			'type' => $item->{type} || 'EMPTY',
			'name' => $window->get_active_name()
		);

		# Channels
		if (defined($item->{type}) && $item->{type} eq 'CHANNEL') {
			$window_data{topic} = $item->{topic};

			my @nicks;
			foreach my $nick ($item->nicks()) {
				push(@nicks, $nick->{nick});
			}
			$window_data{nicks} = \@nicks;
		}

		$window_data{lines} = $self->getWindowLines('refnum' => $refnum);
		return \%window_data;
	}

	sub getWindowLines {
		my $self = shift;
		my %args = @_;
		my $refnum = $args{refnum} or die 'Missing parameter refnum';
		my $timestamp_limit = $args{timestampLimit} || 0;
		my $rowLimit = $args{rowLimit} || 100;

		my $window = Irssi::window_find_refnum($refnum);
		unless ($window) {return [];};
		my $view = $window->view;
		my $buffer = $view->{buffer};
		my $line = $buffer->{cur_line};

		# Return empty if no (new) lines
		if (!defined($line) || $line->{info}->{time} <= $timestamp_limit) {
			return [];
		}

		# Scroll backwards until we find first line we want to add
		while($rowLimit) {
			my $prev = $line->prev();
			if ($prev and ($prev->{info}->{time} > $timestamp_limit)) {
				$line = $prev;
				$rowLimit--;
			} else {
				# Break from loop if list ends
				$rowLimit = 0;
			}
		}

		my @linesArray;
		# Scroll forwards and add all lines till end
		while($line) {
			push(@linesArray, {
				'timestamp' => $line->{info}->{time},
				'text' => $line->get_text(0),
			});
			$line = $line->next();
		}

		return \@linesArray;
	}

	sub sendMessage {
		my $self = shift;
		my %args = @_;
		my $refnum = $args{refnum} or die 'Missing parameter refnum';
		my $message = $args{message} or die 'Missing parameter message';

		# Say to channel on window
		my $window = Irssi::window_find_refnum($refnum);
		unless ($window) {return;};

		my $item = $window->{active};
		if (defined($item->{type}) && $item->{type} eq 'CHANNEL' || $item->{type} eq 'QUERY') {
			$item->command("msg * $message");
		}

		return undef;
	}
}

##
#   Signal handling
##
sub print_text_event {
	#  "print text", TEXT_DEST_REC *dest, char *text, char *stripped
	my ($dest, $text, $stripped) = @_;

	# XXX: Should follow theme format
	my ($sec,$min,$hour) = localtime(time);
	my $formatted_text = "$hour:$min $stripped";

	my $json = {
		'window' => $dest->{window}->{refnum},
		'text' => $formatted_text
	};
	#send_to_clients($json);
}



##
#   HTTP stuff
##
sub handle_http_message {
	my ($connection) = @_;
	my $client_conn = $connection->{handle};
	my $request = $client_conn->get_request();

	if ($request) {
		my $response;
		try {
			$response = handle_http_request($request, $connection);
		} catch {
			$response = HTTP::Response->new(RC_INTERNAL_SERVER_ERROR);
		};
		if ($response) {
			$client_conn->send_response($response);
			if ($response->header('connection') || '' eq 'close') {
				logg('Closing connection: ' . $response->status_line());
				destroy_connection($connection);
			}
		}
	} else {
		logg('Closing connection: ' . $client_conn->reason(), MSGLEVEL_CLIENTCRAP);
		destroy_connection($connection);
	}
}

sub handle_http_request {
	my ($http_request, $connection) = @_;
	my $http_response;

	unless (is_authenticated($http_request)) {
		$http_response = HTTP::Response->new(RC_UNAUTHORIZED);
		logg('Unauthorized request', 'WARNING');
		return $http_response;
	}

	if ($http_request->url =~/^\/rpc(\?.*)?$/) {
		# HTTP RPC calls
		my $call = $marshaller->request_to_call($http_request);
		logg('Received command: ' . $call->method());
		my $res = $call->call($commander);
		return $marshaller->result_to_response($res);
	} elsif ($http_request->method eq 'GET' && $http_request->url =~ /^\/websocket\/?$/) {
		# Handle websocket initiations
		logg('Starting websocket');
		my $hs = Protocol::WebSocket::Handshake::Server->new();
		my $frame = $hs->build_frame();

		my $handle = $connection->{handle};
		$connection->{handshake} = $hs;
		$connection->{frame} = $frame;

		$hs->parse($http_request->as_string);
		print($handle, $hs->to_string);
		$connection->{isWebsocket} = 1;
		logg('WebSocket started');

		return undef;
	} else {
		# NOT found
		return HTTP::Response->new(RC_NOT_FOUND);
	}
}

sub is_authenticated {
	my ($request) = @_;
	my $password = Irssi::settings_get_str('rest_password');
	if ($password) {
		my $request_header = $request->header('Secret');
		return defined($request_header) && $request_header eq $password;
	} else {
		return 1;
	}
}


###
#   WebSocket stuff
###
sub handle_websocket_message {
	my ($connection) = @_;
	my $client_conn = $connection->{handle};
	my $frame = $connection->{frame};

	my $rs = $client_conn->sysread(my $chunk, 1024);
	if ($rs) {
		$frame->append($chunk);
		while (my $message = $frame->next()) {
			if ($frame->is_close()) {
				my $hs = $connection->{handshake};
				# Send close frame back
				my $frame = $hs->build_frame(type => 'close', version => 'draft-ietf-hybi-17');
				print($client_conn, $frame->to_bytes());
			} else {
				# Handle message
				my $call = $marshaller->json_to_call($message);
				logg('received command: ' . $call->method());
				my $res = $call->call($commander);
				my $json_response = $marshaller->return_to_json($res);
				$client_conn->send_response($json_response);
			}
		}
	} else {
		destroy_connection($connection);
	}
}


##
#   Socket handling
##
sub setup_tcp_socket {
	my $server_port = Irssi::settings_get_int('rest_port');
	my $handle = HTTP::Daemon->new(LocalPort => $server_port,
											Type      => SOCK_STREAM,
											Reuse     => 1,
											Listen    => 1 )
		or die "Couldn't be a tcp server on port $server_port : $@\n";
	$server->{handle} = $handle;
	logg("HTTP server started on port " . $server_port, 1);

	# Add handler for server connections
	my $tag = Irssi::input_add(fileno($handle),
								   Irssi::INPUT_READ,
								   \&handle_connection, $server);

	$server->{tag} = $tag;
	%connections = ();
}

sub handle_connection {
	my ($server) = @_;
	my $handle = $server->{handle}->accept();
	logg("Client connected from " . $handle->peerhost());

	my $connection = {
		"handle" => $handle,
		"tag" => 0,
	};

	# Add handler for connection messages
	my $tag = Irssi::input_add(fileno($handle),
								   Irssi::INPUT_READ,
								   \&handle_message, $connection);
	$connection->{tag} = $tag;
	$connections{$tag} = $connection;
}

sub handle_message {
	my ($connection) = @_;
	unless ($connection->{handle}->connected()) {
		return;
	}
	if ($connection->{frame}) {
		handle_websocket_message($connection);
	} else {
		handle_http_message($connection);
	}
}

sub destroy_connections {
	foreach (keys(%connections)) {
		destroy_connection($connections{$_});
	}
}

sub destroy_connection {
	my ($connection) = @_;
	my $tag = $connection->{tag};
	destroy_socket($connection);
	delete($connections{$tag});
}

sub destroy_socket {
	my ($socket) = @_;
	Irssi::input_remove($socket->{tag});
	delete($socket->{tag});
	if (defined($socket->{handle})) {
		close($socket->{handle});
		delete($socket->{handle});
	}
}

sub destroy_sockets {
	destroy_connections();
	destroy_socket($server);
}


##
#   Misc stuff
##
sub logg {
	my ($message, $level) = @_;
	Irssi::print("%B>>%n $IRSSI{name}: $message", MSGLEVEL_CLIENTCRAP);
}

# Run
LOAD();
1;
