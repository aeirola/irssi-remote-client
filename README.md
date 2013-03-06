irssi-client
============

Plugin and clients for remotely operating irssi.

Extending the idea of the irssi-notify script to enable two-way communication and interaction. This is like an combination of irssi-connectbot and irssi-notify, the idea is to make it as easy as possible to operate irc from mobile hardware platforms.

The irssi-script listens to a TCP port or pipe or fifo file or something and provides an API for clients connecting to the script. Over the API the client can fetch information on windows and their content, as well as send commands to irssi.

At the moment the client listens HTTP requests on port 10000, and reacts to the following commands:


REST API
-----------

GET /windows
Returns an list of window objects including the number, name and channel

GET /windows/[number]
Returns window information with nicks and lines and stuff

POST /windows/[number]
Writes a line to the given window number


Usage example
-------------
* `/script load irssi-client-http`
* open `http://localhost:10000/windows`

There is also an silly JS-client that uses the REST API, you need to specify the API base url as an url parameter, like `../client.html?url=http://localhost:10000`


Known issues
------------
* Probably leaks connections or something
* Doesn't have much error handling

Future improvements
-------------------
* Partial scrollback update (fetch lines between given timestamps, or something)
* Use web sockets
* Use shared secret header
* More commands
