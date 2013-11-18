# irssi-client-api.pl -- enables remote control of irssi

use strict;

use Irssi;          # Interfacing with irssi

use HTTP::Daemon;   # HTTP connections
use HTTP::Status;   # HTTP Status codes
use HTTP::Response; # HTTP Responses

use URI;
use URI::QueryParam;

use Protocol::WebSocket;
use JSON;           # Producing JSON output

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
    authors     => 'Axel Eirola',
    contact     => 'axel.eirola@iki.fi',
    name        => 'irssi rest api',
    description => 'This script allows ' .
                   'remote clients to  ' .
                   'control irssi via REST API',
    license     => 'Public Domain',
);

our ($server,           # Stores the server information
     %connections,      # Stores client connections information
);

sub add_settings {
    Irssi::settings_add_int('rest', 'rest_tcp_port', 10000);
    Irssi::settings_add_str('rest', 'rest_password', 'd0ntLe@veM3');
}

sub setup {
    add_settings();
    setup_tcp_socket();

    Irssi::signal_add_last("print text", "print_text_event");
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
        "window" => $dest->{window}->{refnum},
        "text" => $formatted_text
    };
    send_to_clients($json);
}


##
#   Command handling
##
sub perform_command {
    my ($request) = @_;
    my $method = $request->method;
    my $url = $request->uri->path;

    my $data = $request->content;

    # Debug, write every processed command
    log_to_console("received command: $method $url $data");

    my $json;

    if ($method eq "GET" && $url =~ /^\/windows\/?$/) {
        # List all windows
        $json = [];
        foreach (Irssi::windows()) {
            my $window = $_;
            my @items = $window->items();
            my $item = $items[0];

            my $windowJson = {
                "refnum" => $window->{refnum},
                "type" => $item->{type} || "EMPTY",
                "name" => $item->{name} || $window->{name},
                "topic" => $item->{topic}
            };
            push(@$json, $windowJson);
        }
    } elsif ($method eq "GET" && $url =~ /^\/windows\/([0-9]+)\/?$/) {
        my $window = Irssi::window_find_refnum($1);
        if ($window) {
            my @items = $window->items();
            my $item = $items[0];

            $json = {
                "refnum" => $window->{refnum},
                "type" => $item->{type} || "EMPTY",
                "name" => $item->{name} || $window->{name},
                "topic" => $item->{topic}
            };

            # Nicks
            if ($item->{type}) {
                my $nicksJson = [];
                my @nicks = $item->nicks();
                foreach (@nicks) {
                    push(@$nicksJson, $_->{nick});
                }
                $json->{'nicks'} = $nicksJson;
            }

            $json->{'lines'} = getWindowLines($window, $request);
        }
    } elsif ($method eq "GET" && $url =~ /^\/windows\/([0-9]+)\/lines\/?$/) {
        my $window = Irssi::window_find_refnum($1);
        if ($window) {
            $json = getWindowLines($window, $request);
        }
    } elsif ($method eq "POST" && $url =~ /^\/windows\/([0-9]+)\/?$/) {
        # Skip empty lines
        return if $data =~ /^\s$/;
        
        # Say to channel on window
        my $window = Irssi::window_find_refnum($1);
        if ($window) {
            my @items = $window->items();
            my $item = $items[0];
            if ($item->{type}) {
                $item->command("msg * $data");
            } else {
                $window->print($data);
            }
        }
    }

    return $json;
}

sub getWindowLines {
    my ($window, $request) = @_;

    my $view = $window->view;
    my $buffer = $view->{buffer};
    my $line = $buffer->{cur_line};

    # Max lines
    my $count = 100;

    # Limit by timestamp
    my $timestampLimit =  $request->uri->query_param("timestamp");
    $timestampLimit = $timestampLimit ? $timestampLimit : 0;

    # Return empty if no new lines
    if ($line->{info}->{time} <= $timestampLimit) {
        return [];
    }

    # Scroll backwards until we find first line we want to add
    while($count) {
        my $prev = $line->prev;
        if ($prev and ($prev->{info}->{time} > $timestampLimit)) {
            $line = $prev;
            $count--;
        } else {
            # Break from loop if list ends
            $count = 0;
        }
    }

    my $linesArray = [];
    # Scroll forwards and add all lines till end
    while($line) {
        push(@$linesArray, {
            "timestamp" => $line->{info}->{time},
            "text" => $line->get_text(0),
        });
        $line = $line->next();
    }

    return $linesArray;
}


##
#   HTTP stuff
##
sub handle_http_request {
    my ($connection) = @_;
    my $client = $connection->{handle};
    my $request = $client->get_request();

    unless ($request) {
        log_to_console("Closing connection: " . $client->reason, MSGLEVEL_CLIENTCRAP);
        destroy_connection($connection);
        return;
    }

    # Handle websocket initiations
    if ($request->method eq "GET" && $request->url =~ /^\/websocket\/?$/) {
        log_to_console("Starting websocket");
        my $hs = Protocol::WebSocket::Handshake::Server->new;
        my $frame = $hs->build_frame;
        
        $connection->{handshake} = $hs;
        $connection->{frame} = $frame;

        $hs->parse($request->as_string);
        print $client $hs->to_string;
        $connection->{isWebsocket} = 1;
        if (!Irssi::settings_get_str('rest_password')) {
            $connection->{isAuthenticated} = 1;
        }
        log_to_console("WebSocket started");

        return;
    }

    unless (isAuthenticated($request)) {
        my $response = HTTP::Response->new(RC_UNAUTHORIZED);
        $response->header('Content-Type' => 'application/json');
        $response->content("\n");
        $client->send_response($response);
        return;
    }

    my $response = HTTP::Response->new(RC_OK);
    my $responseJson = perform_command($request);
    $response->header('Content-Type' => 'application/json');
    $response->header('Access-Control-Allow-Origin' => '*');

    if ($responseJson) {
        $response->content(to_json($responseJson, {utf8 => 1, pretty => 1}));
    } else {
        $response->content("\n");
    }

    $client->send_response($response);
}

sub isAuthenticated {
    my ($request) = @_;
    my $password = Irssi::settings_get_str('rest_password');
    if ($password) {
        my $requestHeader = $request->header("Secret");
        return defined($requestHeader) && $requestHeader eq $password;
    } else {
        return 1;
    }
}


###
#   WebSocket stuff
###
sub handle_websocket_message {
    my ($connection) = @_;
    my $client = $connection->{handle};
    my $frame = $connection->{frame};

    my $rs = $client->sysread(my $chunk, 1024);
    if ($rs) {
        $frame->append($chunk);
        while (my $message = $frame->next) {
            if ($frame->is_close) {
                my $hs = $connection->{handshake};
                # Send close frame back
                print $client $hs->build_frame(type => 'close', version => 'draft-ietf-hybi-17')->to_bytes;
                return;
            } else {
                # Authentiacte
                my $json = from_json($message, {utf8 => 1});
                if ($json->{method} eq "authenticate" and 
                        $json->{secret} eq Irssi::settings_get_str('rest_password')) {
                    $connection->{isAuthenticated} = 1;
                }
            }
        }
    } else {
        destroy_connection($connection);
    }
}

sub send_to_client {
    my ($message, $connection) = @_;
    my $client = $connection->{handle};
    my $frame = $connection->{frame};

    print $client $frame->new($message)->to_bytes();
}

sub send_to_clients {
    my ($json) = @_;
    my $message = to_json($json, {utf8 => 1, pretty => 1});
    foreach (keys %connections) {
        my $connection = $connections{$_};
        if ($connection->{isWebsocket} and $connection->{isAuthenticated}) {
            send_to_client($message, $connection);
        }
    }
}


##
#   Socket handling
##
sub setup_tcp_socket {
    my $server_port = Irssi::settings_get_int('rest_tcp_port');
    my $handle = HTTP::Daemon->new(LocalPort => $server_port,
                                            Type      => SOCK_STREAM,
                                            Reuse     => 1,
                                            Listen    => 1 )
        or die "Couldn't be a tcp server on port $server_port : $@\n";
    $server->{handle} = $handle;
    log_to_console("HTTP server started on port " . $server_port, 1);

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
    $handle->timeout(1);
    log_to_console("Client connected on " . fileno($handle));

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
        handle_http_request($connection);
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

sub destroy_server {
    destroy_socket($server);
}

sub destroy_sockets {
    destroy_connections();
    destroy_server();
}


##
#   Misc stuff
##
sub UNLOAD() {
    destroy_sockets();
}

sub log_to_console {
    my ($message, $level) = @_;
    Irssi::print("%B>>%n $IRSSI{name} $message", MSGLEVEL_CLIENTCRAP);
}

# Setup on load
setup();

1;
