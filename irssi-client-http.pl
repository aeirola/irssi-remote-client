# irssi-client-api.pl -- enables remote control of irssi

use strict;

use Irssi;          # Interfacing with irssi
use Irssi::TextUI;  # Accessing scrollbacks

use HTTP::Daemon;   # HTTP connections
use HTTP::Status;   # HTTP Status codes
use HTTP::Response; # HTTP Responses

use JSON;           # Producing JSON output

use vars qw($VERSION %IRSSI);

$VERSION = '0.01';
%IRSSI = (
    authors     => 'Axel Eirola',
    contact     => 'axel.eirola@iki.fi',
    name        => 'irssi client api',
    description => 'This script allows ' .
                   'remote clients to  ' .
                   'control irssi.',
    license     => 'Public Domain',
);

our($server,            # Stores the server filehandle
    $server_tag,        # Stores the irssi tag of the server input listener
    $client,            # Stores the client filehandle (should maybe be an array)
    $client_tag,        # Stores the irssi tag of the client input listener
);

sub add_settings {
    Irssi::settings_add_int('rest', 'rest_tcp_port', 10000);
    Irssi::settings_add_str('rest', 'rest_password', 's3cr3t');
}

sub setup {
    Irssi::print("%B>>%n Setting up client api", MSGLEVEL_CLIENTCRAP);
    add_settings();
    setup_tcp_socket();
}

##
#   Socket handling
##
sub setup_tcp_socket() {
    my $server_port = Irssi::settings_get_int('rest_tcp_port');
    $server = HTTP::Daemon->new(LocalPort => $server_port,
                                Type      => SOCK_STREAM,
                                Reuse     => 1,
                                Listen    => 1 )
        or die "Couldn't be a tcp server on port $server_port : $@\n";

    # Add handler for server connections
    $server_tag = Irssi::input_add(fileno($server),
                                   Irssi::INPUT_READ,
                                   \&handle_http_connection, '');

    Irssi::print("%B>>%n Client api set up in tcp mode", MSGLEVEL_CLIENTCRAP);
}

sub handle_http_connection() {
    destroy_socket_client();
    $client = $server->accept();

    # Add handler for client messages
    $client_tag = Irssi::input_add(fileno($client),
                                   Irssi::INPUT_READ,
                                   \&handle_http_request, '');
}

sub handle_http_request() {
    my $request = $client->get_request;

    if (!$request) {
        Irssi::print("%B>>%n: Closing connection: " . $client->reason, MSGLEVEL_CLIENTCRAP);
        destroy_socket_client();
        return;
    }

    if (!isAuthenticated($request)) {
        $client->send_error(RC_UNAUTHORIZED);
        return;
    }

    my $response = HTTP::Response->new(RC_OK);
    my $responseJson = perform_command($request);
    $response->header('Content-Type' => 'application/json');
    $response->header('Access-Control-Allow-Origin' => '*');
    
    if ($responseJson) {
        $response->content(to_json($responseJson, {utf8 => 1, pretty => 1}));
    }
    
    $client->send_response($response);
}

sub isAuthenticated($) {
    my $request = shift;
    my $password = Irssi::settings_get_str('rest_password');
    if ($password) {
        my $requestHeader = $request->header("Secret");
        return $requestHeader eq $password;
    } else {
        return 1;
    }
}

sub destroy_socket_client() {
    Irssi::input_remove($client_tag);
    undef($client_tag);
    if (defined $client) {
        close($client);
        undef($client);
    }
}

sub destroy_socket_server() {
    Irssi::input_remove($server_tag);
    undef($server_tag);
    if (defined $server) {
        close($server);
        undef($server);
    }
}

sub destroy_socket() {
    destroy_socket_client();
    destroy_socket_server();
}

##
#   Command handling
##
sub perform_command($) {
    my $request = shift;
    my $method = $request->method;
    my $url = $request->uri->path;
    my $data = $request->content;

    # Debug, write every processed command
    Irssi::print(
        "%B>>%n $IRSSI{name} received command: $method $url $data",
        MSGLEVEL_CLIENTCRAP);
    

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

            # Scrollback            
            my $linesJson = [];
            my $view = $window->view;

            # Alternative version for limiting
            my $buffer = $view->{buffer};
            my $line = $buffer->{cur_line};
            my $count = 100;

            # Scroll backwards till count
            while($count) {
                if ($line->prev()) {
                    $line = $line->prev();
                    $count--;
                } else {
                    $count = 0;
                }
            }

            # Scroll forwards till end
            while($line) {
                push(@$linesJson, $line->get_text(0));
                $line = $line->next();
            }

            $json->{'lines'} = $linesJson;
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
    } else {
        $json = {
            "GET" => {
                "windows" => "List all windows",
                "windows/[window_id]" => "List window content"
            },
            "POST" => {
                "windows/[id]" => "Post message to window"
            }
        };
    }

    return $json;
}

##
#   Misc stuff
##
sub teardown() {
    destroy_socket();
}

# Setup on load
setup();

# Teardown on unload
Irssi::signal_add_first
    'command script unload', sub {
        my ($script) = @_;
        return unless $script =~
            /(?:^|\s) $IRSSI{name}
             (?:\.[^. ]*)? (?:\s|$) /x;
        teardown();
        Irssi::print("%B>>%n $IRSSI{name} $VERSION unloaded", MSGLEVEL_CLIENTCRAP);
    };    
Irssi::print("%B>>%n $IRSSI{name} $VERSION (by $IRSSI{authors}) loaded", MSGLEVEL_CLIENTCRAP);
