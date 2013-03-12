$(document).ready(onReady);

var baseUrl = '.';
var password = 'd0ntLe@veM3';

var LARGE_INT = 900719925;	// For scrolling the main window, $.scrollTop() works wierdly

var windowNumber = 1;
var lastTimestamp = 0;
var websocket;

function onReady() { 'use strict';
	baseUrl = getParameterByName('url') || '.';
	getWindows();

	var input = $('#input');
	input.keypress(function(e) {
		if (e.which == 13) {
			sendMessage(input.val());
			input.val("");
		}
	});
	
	connectWebSocket();
	setFocus();
}

function setFocus() { 'use strict';
	$('#input').focus();
}

function connectWebSocket() { 'user strict';
	websocket = new WebSocket(baseUrl.replace("http", "ws")+'/websocket');
	websocket.onmessage = function(event) {
		var message = JSON.parse(event.data);
		console.log(message);
		if (message.window === windowNumber) {
			addLines([{timestamp : 0, text: message.text}]);
		} else {
			// Todo activity indication
		}
	};
}

function getParameterByName(name) {
	name = name.replace(/[\[]/, "\\\[").replace(/[\]]/, "\\\]");
	var regexS = "[\\?&]" + name + "=([^&#]*)";
	var regex = new RegExp(regexS);
	var results = regex.exec(window.location.search);
	if (results == null) {
		return "";
	} else {
		return decodeURIComponent(results[1].replace(/\+/g, " "));
	}
}

function addAuthHeader(xhr) {
	xhr.setRequestHeader('Secret', password)
}

function getWindows() { 'use strict';
	$.ajax({
		type: 'GET',
		url: baseUrl+'/windows',
		dataType: 'json',
		cache: false,
		beforeSend: addAuthHeader,
		success: function(windows) {
			var list = $("#windows");
			$.each(windows, function() {
				var item = $('<div>');
				var win = this;
				item.append($('<span>').append(win.refnum + ": " + win.name));
				item.click(function() {
					switchWindow(win.refnum);
				});
				list.append(item);
			});
			switchWindow(windows[0].refnum);
		}
	});
}

function switchWindow(newWindowNumber) { 'use strict';
	windowNumber = newWindowNumber;
	reloadWindow();
	setFocus();
}

function reloadWindow() { 'use strict';
	$.ajax({
		type: 'GET',
		url: baseUrl+'/windows/'+windowNumber,
		dataType: 'json',
		cache: false,
		beforeSend: addAuthHeader,
 		success: function(win) {
			$('#topic').html(win.topic);
			$('#channelName').html(win.name);
			var scrollback = $('#scrollback');
			scrollback.empty();
			addLines(win.lines);

			var nicks = $('#nicks');
			nicks.empty();
			if (win.nicks) {
				$.each(win.nicks, function() {
					var text = this;
					var nick = $('<div>').append(text);
					// Add nick-completion
					nick.click(function(){
						var input = $('#input');
						input.val(input.val() + text + ": ");
						setFocus();
					});
					nicks.append(nick);
				});
			}
		}
	});
}

function addLines(lines) {
	var scrollback = $('#scrollback');
	$.each(lines, function() {
		addLine(this, scrollback);
	});
	scrollback.scrollTop(LARGE_INT);
}

function addLine(line, scrollback) {
	scrollback.append($('<span>').append(line.text));
	lastTimestamp = line.timestamp;
};

function sendMessage(message) { 'use strict';
	if (websocket && false) {
		websocket.send(message);
	} else {
		$.ajax({
			type: 'POST',
			url: baseUrl+'/windows/'+windowNumber,
			data: message
		});
	}
}
