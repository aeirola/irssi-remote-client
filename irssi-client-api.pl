# irssi-client-api.pl -- enables remote control of irssi

use strict;

use Irssi;      # For interfacign with irssi
use IO::Socket; # For TCP connections
use Cwd;
#use JSON;       # For priducing JSON output
use Fcntl;          # provides `O_NONBLOCK' and `O_RDONLY' constants

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
    $fifo,              # Stores the fifo filehandle
    $fifo_tag           # Stores the irssi tag of the fifo input listener
);

sub add_settings {
    Irssi::settings_add_int('client', 'client_tcp_port', 10000);
    #Irssi::settings_add_str('client', 'client_password', 's3cr3t');
    Irssi::settings_add_str('client', 'client_ipc_file', 'client.socket');
    Irssi::settings_add_str('client', 'client_fifo_file', 'client.fifo');
    Irssi::settings_add_str('client', 'client_mode', 'ipc');
}

sub setup {
    Irssi::print("%B>>%n Setting up client api", MSGLEVEL_CLIENTCRAP);
    add_settings();
    
    my $mode = Irssi::settings_get_str('client_mode');
    if ($mode eq 'fifo') {
        setup_fifo();
    } elsif ($mode eq 'tcp') {
        setup_tcp_socket();
    } elsif ($mode eq 'ipc') {
        setup_ipc_socket();
    } else {
        Irssi::print "Unkown client_mode $mode, please set to 'fifo', 'ipc' or 'tcp'.";
    }
}

##
#   FIFO handling
##
sub setup_fifo() {
    my $fifo_path = get_path(Irssi::settings_get_str('client_fifo_file'));
    create_fifo($fifo_path);
    open_fifo($fifo_path);
    Irssi::print("%B>>%n Client api set up in fifo mode", MSGLEVEL_CLIENTCRAP);
}

sub create_fifo($) {
    my ($fifo_path) = @_;
    if (not -p $fifo_path) {
        if (system "mkfifo '$fifo_path' &>/dev/null" and
            system "mknod  '$fifo_path' &>/dev/null"){
            print CLIENTERROR "`mkfifo' failed -- could not create named pipe";
            return "";
        }
    }
}

sub open_fifo($) {
    my ($fifo_path) = @_;
    if (not sysopen $fifo, $fifo_path, O_NONBLOCK | O_RDONLY) {
        print CLIENTERROR "could not open named pipe for reading";
        return "";
    }
    $fifo_tag = Irssi::input_add(fileno($fifo), 
                                 Irssi::INPUT_READ,
                                 \&handle_fifo_message, '');
}

sub handle_fifo_message() {
    foreach (<$fifo>) {
        my @args = ($_, $fifo);
        perform_command(\@args);
    }
}

sub destroy_fifo() {
    Irssi::input_remove($fifo_tag);
    close($fifo);
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

sub open_ipc_socket() {
    my $socket_file = get_path(Irssi::settings_get_str('client_ipc_file'));
    unlink($socket_file);
    $server = IO::Socket::UNIX->new(Local  => $socket_file,
                                    Type   => SOCK_STREAM,
                                    Listen => 1 )
        or die "Couldn't be a ipc server on file $socket_file : $@\n";
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
    
    print "Client connected at " . fileno($client);
    print $client "This is irssi-client-script\n";
    
    # Add handler for client messages
    $client_tag = Irssi::input_add(fileno($client),
                                   Irssi::INPUT_READ,
                                   \&handle_socket_message, '');
}

sub handle_socket_message() {
    my $msg;
    $client->recv($msg, 1024);
    if ($msg =~ /^bye$/ or $msg eq "" ) {
        print $client "Thankyoucomeagain\n";
        destroy_socket_client();
    } else {
        my @args = ($msg, $client);
        perform_command(\@args);
    }
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
    my ($msg, $write) = @$args;

    # Debug, write every processed command
    Irssi::print(
        "%B>>%n $IRSSI{name} received command: \"$msg\"",
        MSGLEVEL_CLIENTCRAP);
    
    if ($msg =~ /^windows$/) {
        # List all windows
        foreach (Irssi::windows()) {
            print $write $_->{refnum} . " " . $_->{name} . "\n";
        }
    } elsif ($msg =~ /^say ([0-9]+) (.*)$/) {
        # Say to channel on window
        my $window = Irssi::window_find_refnum($1);
        if ($window) {
            print $write $window->command("msg * $2");
        } else {
            print $write "Window $1 not found\n";
        }
    } else {
        # Echo failed
        print $write "fail: " . $msg;
    }
    
    # End output with empty line
    print $write "\n";
    print $write "\n";
}

##
#   Misc stuff
##
sub teardown() {
    destroy_socket();
    destroy_fifo();
}


sub get_path($) {
    my ($relative_path) = @_;
    return Cwd::abs_path(Irssi::get_irssi_dir() . "/$relative_path");
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
