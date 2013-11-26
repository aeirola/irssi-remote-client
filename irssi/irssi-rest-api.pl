# irssi-client-api.pl -- enables remote control of irssi

use strict;

use Irssi;          # Interfacing with irssi
use JSON::RPC::Common::Marshal::HTTP;   # JSON-RPC handling

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

our $commander;			# Stores the object which contains the json-rpc commands
our $marshaller;		# Stores the json-rpc marshaller

##
#   Entry points
##


=pod
Called at start of script
=cut
sub LOAD {
	Irssi::settings_add_int('rest', 'rest_port', 10000);
	Irssi::settings_add_str('rest', 'rest_password', 'd0ntLe@veM3');
	Irssi::settings_add_str('rest', 'rest_log_level', 'INFO');

	$commander = Irssi::JSON::RPC::Commander->new();
	$marshaller = JSON::RPC::Common::Marshal::HTTP->new();

	Irssi::signal_add_last("print text", sub {Irssi::JSON::RPC::EventHandler->handle_print_text_event(@_);});
	Irssi::JSON::RPC::HTTP->setup_tcp_socket();
}

=pod
Called by Irssi at script unload time
=cut
sub UNLOAD {
	Irssi::JSON::RPC::HTTP->destroy_sockets();
}

=pod
Called when settings change

# TODO: Add signal listener for settings change
=cut
sub RELOAD {
	Irssi::JSON::RPC::HTTP->destroy_sockets();
	Irssi::JSON::RPC::HTTP->setup_tcp_socket();
}


{
=pod
	Class containing all the methods made available through the JSON-RPC API
=cut
	package Irssi::JSON::RPC::Commander;

	use Irssi::TextUI;  # Enable access to scrollback history, Irssi::UI::Window->view is defined here!

=pod
	Plain constructor

	Returns: new Commander object
=cut
	sub new {
		return bless {}, shift;
	}

=pod
	Get windows

	Returns: a list of window objects
=cut
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

=pod
	Get window

	Named params
	 - refnum (int): Window reference number

	Returns: a window object
=cut
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

=pod
	Get window lines

	Names params:
	 - refnum (int): Window reference number
	 - timestampLimit (int): Minimum age (in seconds since epoch) of line to return
	 - rowLimit (int): Max number of rows to return
	 - timeout (int): Number of seconds to wait for lines

	Returns: 
	<If no timeout, or lines available>:
		a list of line objects containing timestamp and text
	<If timeout given and no lines available>:
		a deferred response definition object



	=item Deferred return values flow

	getWindowLines
	 - registers an event listener for the new line event
	 - registers an timeout for the thing
	 - returns an hash
		{
			deferred: unique field oro object type!
			timeout tag => $tag
			event listener tag => $tag
			resultHandler => undef (function)
		}

	JSON handler
	 - intercepts response using deferred unique field
	 - adds appropriate resultHandler to the deferred definition event
	 - returns without response to client

	eventHandler is called from timeout or line event
	 - removes timeout
	 - removes event handler
	 - creates response data
	 - calls result handler
=cut
	sub getWindowLines {
		my $self = shift;
		my %args = @_;
		my $refnum = $args{refnum} or die 'Missing parameter refnum';
		my $timestamp_limit = $args{timestampLimit} || 0;
		my $rowLimit = $args{rowLimit} || 100;
		my $timeout = $args{timeout};

		my $window = Irssi::window_find_refnum($refnum);
		unless ($window) {return [];};
		my $view = $window->view;
		my $buffer = $view->{buffer};
		my $line = $buffer->{cur_line};

		# Return empty if no (new) lines
		if (!defined($line) || $line->{info}->{time} <= $timestamp_limit) {
			if ($timeout) {
				# Wait for lines, return a deferred response definition object

				# TODO: Clean up some
				my $deferred = Irssi::JSON::RPC::DeferredResponse->new('refnum' => $refnum);
				my $event_handler = sub {
					shift; # Remove class param
					$deferred->handle_event(@_);
				};
				$deferred->{timeout_tag} = Irssi::timeout_add_once($timeout*1000, $event_handler);
				Irssi::JSON::RPC::EventHandler->add_text_listener($refnum, $event_handler);
				return $deferred;
			} else {
				return [];
			}
		}

		# Scroll backwards until we find first line we want to add
		while($rowLimit > 1) {
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

=pod
	send message

	Send message to window if the active item is a channel or a query

	Named params:
	 - refnum: (int) Window reference number
	 - message: (string) Message to send to the window
=cut
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

{
	package Irssi::JSON::RPC::EventHandler;
	##
	#   Event handling
	##

	our %text_listeners = ();# Stores deferred text events

=pod
	Handles writing of message events to deferred responses
=cut
	sub handle_print_text_event {
		#  "print text", TEXT_DEST_REC *dest, char *text, char *stripped
		my ($class, $dest) = @_;

		my $refnum = $dest->{window}->{refnum};

		my $funs = $text_listeners{$refnum};
		if (defined($funs)) {
			for my $fun (@$funs) {
				&$fun(@_);
			}
			delete($text_listeners{$refnum});
		}

		# XXX: Should follow theme format
		#my ($sec,$min,$hour) = localtime(time);
		#my $formatted_text = "$hour:$min $stripped";

		#my $json = {
		#	'window' => $dest->{window}->{refnum},
		#	'text' => $formatted_text
		#};
		#send_to_clients($json);
	}

	sub add_text_listener {
		my ($class, $refnum, $deffered) = @_;
		unless ($text_listeners{$refnum}) {
			$text_listeners{$refnum} = [];
		}

		push($text_listeners{$refnum}, $deffered);
	}

	sub remove_text_listener {
		my ($refnum) = @_;
		delete($text_listeners{$refnum});
	}
}

{
	package Irssi::JSON::RPC::DeferredResponse;

	sub new {
		my $class = shift;
		my %args = @_;
		return bless {
			'response_handler' => undef,
			'timeout_tag' => undef,
			'refnum' => $args{refnum}
			}, $class;
	}

	sub handle_event {
		my ($self, $dest, $text, $formatted_text) = @_;
		my $data;
		if ($dest) {
			Irssi::timeout_remove($self->{timeout_tag});
			$data = $commander->getWindowLines('refnum' => $dest->{window}->{refnum}, 'rowLimit' => 1);
		} else {
			Irssi::JSON::RPC::EventHandler::remove_text_listener($self->{refnum});
			$data = [];
		}
		my $func = $self->{response_handler};
		&$func($data);
	}
}

{
	package Irssi::JSON::RPC::HTTP;
	##
	#   HTTP stuff
	##
	
	use Try::Tiny;      # try {} catch {}; structure

	use HTTP::Daemon;   # HTTP connections
	use HTTP::Status;   # HTTP Status codes
	use HTTP::Response; # HTTP Responses
	use Protocol::WebSocket;                # Websocket connection handling
	
	our $server;			# Stores the server information
	our %connections = ();	# Stores client connections information


=pod
	Handles a message sent by the client over HTTP

	Params:
		connection: Connection definition hash
=cut
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
					Irssi::JSON::RPC::Misc->logg('Closing connection: ' . $response->status_line());
					destroy_connection($connection);
				}
			}
		} else {
			Irssi::JSON::RPC::Misc->logg('Closing connection: ' . $client_conn->reason());
			destroy_connection($connection);
		}
	}

=pod
	Handles HTTP request sent by client

	Transforms websocket requests to websocket conections

	Params:
		http_request: HTTP::Request object
		connection: Connection definitin hash

	Returns: HTTP::Response object to be sent to client, or undef if nothing is to be sent
=cut
	sub handle_http_request {
		my ($http_request, $connection) = @_;
		my $http_response;

		unless (is_authenticated($http_request)) {
			$http_response = HTTP::Response->new(RC_UNAUTHORIZED);
			Irssi::JSON::RPC::Misc->logg('Unauthorized request', 'WARNING');
			return $http_response;
		}

		if ($http_request->url =~/^\/rpc(\?.*)?$/) {
			# HTTP RPC calls
			my $call = $marshaller->request_to_call($http_request);
			Irssi::JSON::RPC::Misc->logg('Received command: ' . $call->method());
			my $res = $call->call($commander);
			if (ref($res->{result}) eq 'Irssi::JSON::RPC::DeferredResponse') {
				my $client_conn = $connection->{handle};
				$res->{result}->{response_handler} = sub {
					# TODO: Clean up some
					$res->{result} = shift;
					my $response = $marshaller->result_to_response($res);
					$client_conn->send_response($response);
				};
				return undef;
			} else {
				return $marshaller->result_to_response($res);
			}
		} elsif ($http_request->method eq 'GET' && $http_request->url =~ /^\/websocket\/?$/) {
			# Handle websocket initiations
			Irssi::JSON::RPC::Misc->logg('Starting websocket');
			my $hs = Protocol::WebSocket::Handshake::Server->new();
			my $frame = $hs->build_frame();

			my $handle = $connection->{handle};
			$connection->{handshake} = $hs;
			$connection->{frame} = $frame;

			$hs->parse($http_request->as_string);
			print($handle, $hs->to_string);
			$connection->{isWebsocket} = 1;
			Irssi::JSON::RPC::Misc->logg('WebSocket started');

			return undef;
		} else {
			# NOT found
			return HTTP::Response->new(RC_NOT_FOUND);
		}
	}

=pod
	Checks if given http request object is authenticated

	Params:
	 - request: HTTP::Request object

	Returns: (boolean) 1 if authenticated, 0 if not
=cut
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
=pod
	Handles a message sent to a websocket connection

	Params:
	 - connection: Connection definition hash

=cut
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
					Irssi::JSON::RPC::Misc->logg('received command: ' . $call->method());
					my $res = $call->call($commander);
					if (ref($res->{result}) eq 'Irssi::JSON::RPC::DeferredResponse') {
						$res->{result}->{response_handler} = sub {
							my $json_response = $marshaller->return_to_json(shift);
							$client_conn->send_response($json_response);
						};
						return undef;
					} else {
						my $json_response = $marshaller->return_to_json($res);
						$client_conn->send_response($json_response);
					}
				}
			}
		} else {
			destroy_connection($connection);
		}
	}


##
#   Socket handling
##
=pod
	Setups listening of TCP connections on port using Irssi::input_add
=cut
	sub setup_tcp_socket {
		my $server_port = Irssi::settings_get_int('rest_port');
		my $handle = HTTP::Daemon->new(LocalPort => $server_port,
												Type      => SOCK_STREAM,
												Reuse     => 1,
												Listen    => 1 )
			or die "Couldn't be a tcp server on port $server_port : $@\n";
		$server->{handle} = $handle;
		Irssi::JSON::RPC::Misc->logg("HTTP server started on port " . $server_port, 1);

		# Add handler for server connections
		my $tag = Irssi::input_add(fileno($handle),
									   Irssi::INPUT_READ,
									   \&handle_connection, $server);

		$server->{tag} = $tag;
		%connections = ();
	}

=pod
	Handles new incoming TCP connections

	Params:
	 - server (HTTP::Daemon)
=cut
	sub handle_connection {
		my ($server) = @_;
		my $handle = $server->{handle}->accept();
		Irssi::JSON::RPC::Misc->logg("Client connected from " . $handle->peerhost());

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

=pod
	Handles messages sent to open TCP connections

	Params:
	 - connection: Connection definition hash
=cut
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

=pod
	Closes all open connections
=cut
	sub destroy_connections {
		foreach (keys(%connections)) {
			destroy_connection($connections{$_});
		}
	}

=pod
	Closes given connection

	Params:
	 - connection: Connection definition hash
=cut
	sub destroy_connection {
		my ($connection) = @_;
		my $tag = $connection->{tag};
		destroy_socket($connection);
		delete($connections{$tag});
	}

=pod
	Closes an open socket
	Params:
	 - Socket
=cut
	sub destroy_socket {
		my ($socket) = @_;
		Irssi::input_remove($socket->{tag});
		delete($socket->{tag});
		if (defined($socket->{handle})) {
			close($socket->{handle});
			delete($socket->{handle});
		}
	}

=pod
	Destroys all active connections and the server listener
=cut
	sub destroy_sockets {
		destroy_connections();
		destroy_socket($server);
	}
}

{
	package Irssi::JSON::RPC::Misc;
	##
	#   Misc stuff
	##

	use Irssi qw( MSGLEVEL_CLIENTCRAP );

=pod
	Log line to irssi console
=cut
	sub logg {
		my ($class, $message, $level) = @_;
		Irssi::print("%B>>%n $IRSSI{name}: $message", MSGLEVEL_CLIENTCRAP);
	}
}

# Run
LOAD();
1;
