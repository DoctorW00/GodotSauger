class_name WebAPIManager
extends Node

signal data_received(json_data)
signal request_failed(error_message)

func fetch_data(url: String, timeout_seconds: float = 10.0):
	var http = HTTPRequest.new()
	add_child(http)
	http.timeout = timeout_seconds
	http.request_completed.connect(_on_request_completed.bind(http))
	var error = http.request(url)
	if error != OK:
		request_failed.emit("[Web-API] Request error!")
		http.queue_free()

func _on_request_completed(result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if result == HTTPRequest.RESULT_TIMEOUT:
		request_failed.emit("[Web-API] (Timeout).")
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("[Web-API] Connection error (Code: %s)" % result)
		return
	if response_code != 200:
		request_failed.emit("[Web-API] Server error: %s" % response_code)
		return
	var json_string = body.get_string_from_utf8()
	var json = JSON.parse_string(json_string)
	if json == null:
		request_failed.emit("[Web-API] Error reading JSON data!")
		return
	data_received.emit(json)
