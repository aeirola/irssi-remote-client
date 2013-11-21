# irssi-client-api.pl -- enables remote control of irssi
use strict;
use Irssi;          # Interfacing with irssi

use HTTP::Daemon;   # HTTP connections
use HTTP::Status;   # HTTP Status codes
use HTTP::Response; # HTTP Responses
use JSON::RPC::Common::Marshal::HTTP;
use Protocol::WebSocket;

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
    Irssi::settings_add_int('rest', 'rest_tcp_port', 10000);
    Irssi::settings_add_str('rest', 'rest_password', 'd0ntLe@veM3');
    Irssi::settings_add_str('rest', 'rest_log_level', 'INFO');
    setup_tcp_socket();

    Irssi::signal_add_last("print text", "print_text_event");
}

sub UNLOAD {
    # Called by Irssi on unload
    destroy_sockets();
}

sub RELOAD {
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
        my @windows = [];
        foreach my $window (Irssi::windows()) {
            my @items = $window->items();
            my $item = $items[0];
            my %windowData = (
                'refnum' => $window->{refnum},
                'type' => $item->{type} || "EMPTY",
                'name' => $item->{name} || $window->{name}
            );
            push(@windows, %windowData);
        }
        return @windows;
    }

    sub getWindow {
        my ($self, $refnum) = @_;

        my $window = Irssi::window_find_refnum($refnum);
        unless ($window) {return;};

        my @items = $window->items();
        my $item = $items[0];

        my %windowData = (
            'refnum' => $window->{refnum},
            'type' => $item->{type} || "EMPTY",
            'name' => $item->{name} || $window->{name}
        );

        # Channels
        if (defined($item->{type}) && $item->{type} eq "CHANNEL") {
            $windowData{topic} = $item->{topic};

            my @nicks = [];
            foreach my $nick ($item->nicks()) {
                push(@nicks, $nick->{nick});
            }
            $windowData{nicks} = @nicks;
        }

        $windowData{lines} = $self->getWindowLines($refnum);
        return %windowData;
    }

    sub getWindowLines {
        my ($self, $refnum, $timestampLimit) = @_;

        my $window = Irssi::window_find_refnum($1);
        my $view = $window->view;
        my $buffer = $view->{buffer};
        my $line = $buffer->{cur_line};

        # Max lines
        my $count = 100;

        # Return empty if no (new) lines
        if (!defined($line) || $line->{info}->{time} <= $timestampLimit) {
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

        my @linesArray = [];
        # Scroll forwards and add all lines till end
        while($line) {
            push(@linesArray, {
                "timestamp" => $line->{info}->{time},
                "text" => $line->get_text(0),
            });
            $line = $line->next();
        }

        return @linesArray;
    }

    sub sendMessage {
        my ($self, $refnum, $message) = @_;

        # Say to channel on window
        my $window = Irssi::window_find_refnum($refnum);
        unless ($window) {return;};

        my @items = $window->items();
        my $item = $items[0];
        if ($item->{type}) {
            $item->command("msg * $message");
        } else {
            $window->print($message);
        }
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
        "window" => $dest->{window}->{refnum},
        "text" => $formatted_text
    };
    #send_to_clients($json);
}



##
#   HTTP stuff
##
sub handle_http_request {
    my ($connection) = @_;
    my $client = $connection->{handle};
    my $http_request = $client->get_request();

    unless ($http_request) {
        logg("Closing connection: " . $client->reason, MSGLEVEL_CLIENTCRAP);
        destroy_connection($connection);
        return;
    }

    unless (isAuthenticated($http_request)) {
        my $response = HTTP::Response->new(RC_UNAUTHORIZED);
        $response->header('Content-Type' => 'application/json');
        $response->content("\n");
        $client->send_response($response);
        return;
    }

    if ($http_request->url =~/^\/rpc\/?$/) {
        # HTTP RPC calls
        my $call = $marshaller->request_to_call($http_request);
        logg("received command: $call");
        my $res = $call->call($commander);
        my $http_response = $marshaller->result_to_response($res);
        $client->send_response($http_response);
        return;
    } elsif ($http_request->method eq "GET" && $http_request->url =~ /^\/websocket\/?$/) {
        # Handle websocket initiations
        logg("Starting websocket");
        my $hs = Protocol::WebSocket::Handshake::Server->new;
        my $frame = $hs->build_frame;
        
        $connection->{handshake} = $hs;
        $connection->{frame} = $frame;

        $hs->parse($http_request->as_string);
        print $client $hs->to_string;
        $connection->{isWebsocket} = 1;
        logg("WebSocket started");

        return;
    } else {
        # NOT found
        my $response = HTTP::Response->new(RC_NOT_FOUND);
        $response->content("\n");
        $client->send_response($response);
    }
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
            } else {
                # Handle message
                my $call = $marshaller->json_to_call($message);
                logg("received command: $call");
                my $res = $call->call($commander);
                my $json_response = $marshaller->return_to_json($res);
                $client->send_response($json_response);
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
    my $server_port = Irssi::settings_get_int('rest_tcp_port');
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
    logg("Client connected on " . fileno($handle));

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
