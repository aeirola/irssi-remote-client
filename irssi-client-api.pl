# irssi-client-api.pl -- enables remote control of irssi

use strict;

use Irssi;      # For interfacign with irssi
use IO::Socket; # For TCP connections
use JSON;       # For priducing JSON output

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

our ( $server );

sub setup {
    print "Setting up";
    $server = IO::Socket::INET->new(LocalPort => 10000,
                                    Type      => SOCK_STREAM,
                                    Reuse     => 1,
                                    Listen    => 10 )   # or SOMAXCONN
        or die "Couldn't be a tcp server on port 100000 : $@\n";
    
    my @args = ($server);
    print "Server at " . fileno($server);
    # Add handler for server connections
    Irssi::input_add(fileno($server),
                        Irssi::INPUT_READ,
                        \&handle_connection,
                        \@args);
}   

sub handle_connection {
    my $args = shift;
    my ($server) = @$args;
    my $client = $server->accept();
    
    print "Client connected at" . fileno($client);
    print $client "You have connected to irssi-client-script\n";
    
    my @args = ($client);
    # Add handler for client messages
    Irssi::input_add(fileno($client),
                        Irssi::INPUT_READ,
                        \&handle_message,
                        \@args);
}

sub handle_message {
    my $args = shift;
    my ($client) = @$args;
    
    my $msg;
    $client->recv($msg, 1024);
    
    if ($msg =~ /^windows$/) {
        foreach (Irssi::windows()) {
            print $client $_->{refnum} . " " . $_->{name} . "\n";
        }
    } elsif ($msg =~ /^active_window$/) {
        my $win = Irssi::active_win();
        print $client $win->{refnum} . " " . $win->{name} . "\n";
    } elsif ($msg =~ /^bye$/) {
        print $client "Thankyoucomeagain\n";
        close($client);
        Irssi::input_remove(fileno($client));
    } else {
        print $client "echo: " . $msg;
    }
}

sub teardown {
    Irssi::input_remove(fileno($server));
    close($server);
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
print CLIENTCRAP "%B>>%n $IRSSI{name} $VERSION (by $IRSSI{authors}) loaded";

