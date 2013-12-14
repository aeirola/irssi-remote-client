Irssi Remote Client (IRC)
=========================

Script and clients for remotely operating Irssi.

The script is a HTTP server running inside Irssi and listens for commands. Most of the internal complexity of Irssi is hidden by the script, and the functionality is exposed via a simplified interface.

The clients can be anything with an internet connection and talks HTTP. Currently there is only an JavaScript HTML5 application that exposes a chat interface.


Installing
----------

 1. Install script and dependencies (for more information check the script readme):
  * `cpan Try::Tiny JSON::RPC::Common Digest::SHA`
  * `curl -o ~/.irssi/scripts/remote-client.pl https://raw.github.com/aeirola/irssi-remote-client/master/irssi/remote-client.pl`

 2. Load script (in Irssi):
  * `/script load remote-client`
  * `/set remote_client_password $YOUR_PASSWORD`
  * `/set remote_client_port $YOUR_PORT`


Known issues
------------
* Irssi script doesn't have much error handling, might crash randomly
* Limited functionality
* Non-ASCII characters don't render in client
* Long lines and topics break layout flow

Future improvements
-------------------
* JSON-RPC support on WebSocket
* More command functionality
 * Topics
 * Channels
 * Queries
 * Hilights
 * ...
* Reconnection, pings, fault tolerance
* Code cleanup


Similar failed projects
-----------------------
* http://wouter.coekaerts.be/webssi/ : But they used some horrible GWT on the client side
* http://max.kellermann.name/projects/web-irssi/ : But they used a separate CGI script and irssi Perl script
* https://github.com/cho45/Irssw
