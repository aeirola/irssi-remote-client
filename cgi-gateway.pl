#!/usr/local/bin/perl
use strict;

use CGI;
use IO::Socket;

# Define the socket file
my $socket_file = "/Users/aeirola/.irssi/client.socket";

# Create CGI object
my $q = CGI->new;

# Get all post data
my $cmd = $q->param( 'POSTDATA' );

# Print HTTP header
print $q->header(-type=>'text',
                -charset=>'utf-8');


# Open socket
my $sock = IO::Socket::UNIX->new(Peer   => $socket_file,
                                 Type   => SOCK_STREAM)
            or die "Couldn't open socket to $socket_file";

# Write to socket
print $sock "$cmd\n" 
    or die "Couldn't write command to socket";

# Read response
LOOP: while (<$sock>) {
    if ($_ eq "\n") {
        # Close on empty line
        last LOOP;
    } else {
        print $_ or die "Couldn't write response";
    }
}

# Clean up
print $sock "bye\n" or die "Couldn't end connection cleanly";
close($sock) or die "Couldn't close socket";
