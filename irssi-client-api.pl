# irssi-client-api.pl -- enables remote control of irssi

use strict;

use Irssi;      # For interfacign with irssi
use IO::Socket; # For TCP connections
use JSON;       # For priducing JSON output
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
    Irssi::settings_add_int('client', 'client_port', 10000);
    Irssi::settings_add_str('client', 'client_password', 's3cr3t');
    Irssi::settings_add_str('client', 'client_fifo', '~/.irssi/client.fifo');
    Irssi::settings_add_str('client', 'client_mode', 'fifo');
}

sub setup {
    Irssi::print("%B>>%n Setting up client api", MSGLEVEL_CLIENTCRAP);
    add_settings();
    
    my $mode = Irssi::settings_get_str('client_mode');
    if ($mode eq 'fifo') {
        setup_fifo();
    } elsif ($mode eq 'tcp') {
        setup_tcp();
    } else {
        Irssi::print "Unkown client_mode $mode, please set to either 'fifo' or 'tcp'.";
    }
}

##
#   FIFO handling
##
sub setup_fifo() {
    my $fifo_path = Irssi::settings_get_str('client_fifo');
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
#   TCP handling
##
sub setup_tcp() {
    my $server_port = Irssi::settings_get_int('client_port');
    $server = IO::Socket::INET->new(LocalPort => $server_port,
                                    Type      => SOCK_STREAM,
                                    Reuse     => 1,
                                    Listen    => 10 )   # or SOMAXCONN
        or die "Couldn't be a tcp server on port $server_port : $@\n";
    
    print "Server at " . fileno($server);
    # Add handler for server connections
    $server_tag = Irssi::input_add(fileno($server),
                                   Irssi::INPUT_READ,
                                   \&handle_tcp_connection, '');
    Irssi::print("%B>>%n Client api set up in tcp mode", MSGLEVEL_CLIENTCRAP);
}

sub handle_tcp_connection() {
    destroy_tcp_client();
    $client = $server->accept();
    
    print "Client connected at " . fileno($client);
    print $client "You have connected to irssi-client-script\n";
    
    # Add handler for client messages
    $client_tag = Irssi::input_add(fileno($client),
                                   Irssi::INPUT_READ,
                                   \&handle_tcp_message, '');
}

sub handle_tcp_message() {
    my $msg;
    $client->recv($msg, 1024);
    if ($msg =~ /^bye$/ or $msg eq "" ) {
        print $client "Thankyoucomeagain\n";
        destroy_tcp_client();
    } else {
        my @args = ($msg, $client);
        perform_command(\@args);
    }
}

sub destroy_tcp_client() {
    Irssi::input_remove($client_tag);
    if (defined $client) {
        close($client);
    }
}

sub destroy_tcp_server() {
    Irssi::input_remove($server_tag);
    if (defined $server) {
        close($server);
    }
}

sub destroy_tcp() {
    destroy_tcp_client();
    destroy_tcp_server();
}

##
#   Command handling
##
sub perform_command($) {
    my $args = shift;
    my ($msg, $write) = @$args;
    
    Irssi::print(
        "%B>>%n $IRSSI{name} received command: \"$msg\"",
        MSGLEVEL_CLIENTCRAP);
    
    if ($msg =~ /^windows$/) {
        foreach (Irssi::windows()) {
            print $write $_->{refnum} . " " . $_->{name} . "\n";
        }
    } elsif ($msg =~ /^active_window$/) {
        my $win = Irssi::active_win();
        print $write $win->{refnum} . " " . $win->{name} . "\n";
    } else {
        print $write "echo: " . $msg;
    }
}

sub teardown() {
    destroy_tcp();
    destroy_fifo();
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
