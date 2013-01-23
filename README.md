irssi-client
============

Plugin and clients for remotely operating irssi.

Extending the idea of the irssi-notify script to enable two-way communication and interaction. This is like an combination of irssi-connectbot and irssi-notify, the idea is to make it as easy as possible to operate irc from mobile hardware platforms.

The irssi-script listens to a TCP port or pipe or fifo file or something and provides an API for clients connecting to the script. Over the API the client can fetch information on windows and their content, as well as send commands to irssi.

At the moment the client listens to port 10000, and reacts to the following commands:

* `windows`: lists all open windows
* `active_window`: lists active window
* `bye`: closes the connection

Usage example
-------------
* `/script load irssi-client-api`
* `nc localhost 10000` or `socat - UNIX-CLIENT:client.socket`
* `windows`
* `bye`



Known issues
------------
* Freezes irssi on connection close
* Probably leaks connections or something
* Doesn't do much yet
* Might eat a lot of cpu at times?
