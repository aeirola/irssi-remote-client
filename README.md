irssi-rest-api
==============

Plugin and clients for remotely operating irssi.

Extending the idea of the irssi-notify script to enable two-way communication and interaction. This is like an combination of irssi-connectbot and irssi-notify, the idea is to make it as easy as possible to operate irc from mobile hardware platforms.

The irssi-script listens to a TCP port or pipe or fifo file or something and provides an API for clients connecting to the script. Over the API the client can fetch information on windows and their content, as well as send commands to irssi.

At the moment the client listens HTTP requests on port 10000, and reacts to the following commands:

The client interface can be tested with static data at client-js/?url=test_data/




JSON-RPC API
------------

JSON-RPC v2 protocol for controlling irssi


### URLs:
HTTP url: /http (POST)
WebSocket url: /websocket


### Methods:

--> { "method": "getWindows", "id": 1}
<-- { "error": null, "id": 1, "result": 
		{
			1: {
				"name": "#irssi",
				"channel": "#irssi"
			},
			...
		}
	}


--> { "method": "getWindow", "params": {"windowId": 1}, "id": 1}
<-- { "error": null, "id": 1, "result": 
		{
			"name": "#irssi",
			"channel": "#irssi",
			"nicks": [
				{
					"name": "Spaceball",
					"mode": "op"|"voice"|null
				},
				...
			]
		}
	}


--> { "method": "getWindowLines", "params": {"windowId": 1, "timestamp": "2013-10-24T17:04:12.12341"}, "id": 1}
<-- { "error": null, "id": 1, "result": 
		[
			{
				"timestamp": "2013-10-24T17:06:12.54326",
				"text": "<Spaceball> Lol, i'm on irc"
			},
			...
		]
	}


--> { "method": "sendMessage": "params": {"windowId": 1, "message": "Lol, i'm on irc"}, "id": 1}
<-- { "error": null", "id": 1, "result": 
		{
			"timestamp": "2013-10-24T17:10:45.12415",
			"text": "lol, i'm on irc"
		}
	}


Usage example
-------------
* `/script load irssi-rest-api`
* `curl -POST http://localhost:10000/http -d '{ "method": "getWindows", "id": 1}'`

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

Irssi documentation
-------------------
* http://irssi.org/documentation: Official
* https://github.com/shabble/irssi-docs: Unofficial

Similar failed projects
-----------------------
* http://wouter.coekaerts.be/webssi/ : But they used some horrible GWT on the client side
* http://max.kellermann.name/projects/web-irssi/ : But they used a separate CGI script and irssi Perl script
* https://github.com/cho45/Irssw
