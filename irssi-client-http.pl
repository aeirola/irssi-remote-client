# irssi-client-api.pl -- enables remote control of irssi

use strict;

use Irssi;          # Interfacing with irssi
use Irssi::TextUI;  # Accessing scrollbacks
use IO::Socket;     # TCP connections
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
    Irssi::settings_add_int('client', 'client_tcp_port', 10000);
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
    open_tcp_socket();
    listen_socket();
    Irssi::print("%B>>%n Client api set up in tcp mode", MSGLEVEL_CLIENTCRAP);
}

sub open_tcp_socket() {
    my $server_port = Irssi::settings_get_int('client_tcp_port');
    $server = IO::Socket::INET->new(LocalPort => $server_port,
                                    Type      => SOCK_STREAM,
                                    Reuse     => 1,
                                    Listen    => 2 )
        or die "Couldn't be a tcp server on port $server_port : $@\n";
}

sub setup_ipc_socket() {
    open_ipc_socket();
    listen_socket();
    Irssi::print("%B>>%n Client api set up in ipc mode", MSGLEVEL_CLIENTCRAP);
}

sub listen_socket() {
    print "Server at " . fileno($server);
    # Add handler for server connections
    $server_tag = Irssi::input_add(fileno($server),
                                   Irssi::INPUT_READ,
                                   \&handle_socket_connection, '');
}

sub handle_socket_connection() {
    destroy_socket_client();
    $client = $server->accept();
    
    #print "Client connected at " . fileno($client);
    
    # Add handler for client messages
    $client_tag = Irssi::input_add(fileno($client),
                                   Irssi::INPUT_READ,
                                   \&handle_socket_message, '');
}

sub handle_socket_message() {
    my $msg;
    $client->recv($msg, 1024);
    my ($cmd, $url, $data) = $msg =~ /^(GET|POST) ([^ ]+) HTTP\/[^\n]+\n(?:[^\n]+\n)*(.+)$/sm;
    if ($cmd) {
        print $client "HTTP/1.1 200 OK\n";
        print $client "Content-Type: application/json\n";
        print $client "Access-Control-Allow-Origin: *\n";
        print $client "\n";
        my @args = ($cmd, $url, $data, $client);
        perform_command(\@args);
    } else {
        print $client "HTTP/1.1 500 OK\n";
        print $client "\n";
    }

    destroy_socket_client();
}

sub destroy_socket_client() {
    Irssi::input_remove($client_tag);
    if (defined $client) {
        close($client);
    }
}

sub destroy_socket_server() {
    Irssi::input_remove($server_tag);
    if (defined $server) {
        close($server);
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
    my $args = shift;
    my ($cmd, $url, $data, $out) = @$args;

    # Debug, write every processed command
    Irssi::print(
        "%B>>%n $IRSSI{name} received command: $cmd $url $data",
        MSGLEVEL_CLIENTCRAP);
    
    my $json;

    if ($cmd eq "GET" && $url =~ /^\/windows\/?$/) {
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
    } elsif ($cmd eq "GET" && $url =~ /^\/windows\/([0-9]+)\/?$/) {
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

    } elsif ($cmd eq "POST" && $url =~ /^\/windows\/([0-9]+)\/?$/) {
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

    if ($json) {
        print $out to_json($json, {utf8 => 1, pretty => 1});
    }
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
