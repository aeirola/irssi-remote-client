irssi-rest-api
==============

Plugin and clients for remotely operating irssi.

Extending the idea of the irssi-notify script to enable two-way communication and interaction. This is like an combination of irssi-connectbot and irssi-notify, the idea is to make it as easy as possible to operate irc from mobile hardware platforms.

The irssi-script listens to a TCP port or pipe or fifo file or something and provides an API for clients connecting to the script. Over the API the client can fetch information on windows and their content, as well as send commands to irssi.

At the moment the client listens HTTP requests on port 10000, and reacts to the following commands:

The client interface can be tested with static data at client-js/?url=test_data/


REST API
-----------

GET /windows
Returns an list of window objects including the number, name and channel

GET /windows/[number]
Returns window information with nicks and lines and stuff

GET /windows/[number]/lines?timestamp=[limit]
Returns window lines, optionally limited by timestamp param. Useful for updating a view

POST /windows/[number]
Writes a line to the given window number

GET /websocket
Provides websocket connection for receiving notifications

Usage example
-------------
* `/script load irssi-rest-api`
* open `http://localhost:10000/windows`

There is also an silly JS-client that uses the REST API, you need to specify the API base url as an url parameter, like `../client.html?url=http://localhost:10000`

Requirements
------------
* Protocol::WebSocket for handling websocket connections

Known issues
------------
* Probably leaks connections or something
* Doesn't have much error handling

Future improvements
-------------------
* JSON-RPC support on WebSocket?
* Cleaner API
* More commands
* Reconnection, pings, fault tolerance
