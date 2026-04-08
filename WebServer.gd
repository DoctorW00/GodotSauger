'''
extends Node
class_name WWWServer

signal log_requested(text: String, color: String)

@export var port: int = 8080
@export var upload_dir: String = ""

var tcp_server: TCPServer = TCPServer.new()
var server_thread: Thread = Thread.new()
var is_running: bool = false

func _ready() -> void:
	if not DirAccess.dir_exists_absolute(upload_dir):
		DirAccess.make_dir_recursive_absolute(upload_dir)
		log_requested.emit.call_deferred("[WWW] Path created: " + upload_dir)
	start_server()

func _exit_tree() -> void:
	stop_server()

func start_server() -> void:
	var error = tcp_server.listen(port)
	if error != OK:
		log_requested.emit.call_deferred("[WWW] Error creating webserver on port: " + str(port), "red")
		return
	is_running = true
	log_requested.emit.call_deferred("[WWW] Running on port: " + str(port), "orange")
	server_thread.start(Callable(self, "_thread_loop"))

func stop_server() -> void:
	is_running = false
	tcp_server.stop()
	if server_thread.is_started():
		server_thread.wait_to_finish()
	log_requested.emit.call_deferred("[WWW] Webserver stopped!", "orange")

func _thread_loop() -> void:
	while is_running:
		if tcp_server.is_connection_available():
			var peer: StreamPeerTCP = tcp_server.take_connection()
			_handle_client(peer)
		OS.delay_msec(10)

func _handle_client(peer: StreamPeerTCP) -> void:
	var timeout = 5.0
	while peer.get_available_bytes() == 0 and timeout > 0:
		OS.delay_msec(50)
		timeout -= 0.05
	if peer.get_available_bytes() == 0:
		peer.disconnect_from_host()
		return
	var bytes = peer.get_partial_data(peer.get_available_bytes())
	var request_data: PackedByteArray = bytes[1]
	var request_string: String = request_data.get_string_from_utf8()
	if request_string.is_empty():
		peer.disconnect_from_host()
		return
	var lines = request_string.split("\r\n")
	if lines.size() == 0:
		peer.disconnect_from_host()
		return
	var request_line = lines[0]
	if request_line.begins_with("GET"):
		_send_html_page(peer)
	elif request_line.begins_with("POST"):
		_handle_file_upload(peer, request_string, request_data)
	else:
		_send_response(peer, 405, "text/plain", "Method Not Allowed")
	peer.disconnect_from_host()

func _send_html_page(peer: StreamPeerTCP) -> void:
	var html_resource = preload("res://webserver/index.gd")
	if html_resource:
		var html_text = html_resource.HTML
		_send_response(peer, 200, "text/html", html_text)
	else:
		_send_response(peer, 404, "text/plain", "Error: Script-Resource not found!")

func _handle_file_upload(peer: StreamPeerTCP, request_string: String, request_data: PackedByteArray) -> void:
	var boundary = ""
	var lines = request_string.split("\r\n")
	for line in lines:
		if line.begins_with("Content-Type: multipart/form-data; boundary="):
			boundary = line.split("boundary=")[1].strip_edges()
			break
	if boundary == "":
		_send_response(peer, 400, "text/plain", "Bad Request: No Boundary")
		return
	var boundary_bytes = ("--" + boundary).to_utf8_buffer()
	var filename = "unnamed.sfdl"
	var content_disposition = 'filename="'
	var filename_idx = request_string.find(content_disposition)
	if filename_idx != -1:
		var start = filename_idx + content_disposition.length()
		var end = request_string.find('"', start)
		filename = request_string.substr(start, end - start)
		filename = filename.get_file()
		if filename.is_empty(): filename = "unnamed.sfdl"
	var search_string = 'filename="' + filename + '"'
	var file_header_idx = request_string.find(search_string)
	if file_header_idx == -1:
		_send_response(peer, 400, "text/plain", "Dateiformat ungueltig")
		return
	var data_start_idx = request_string.find("\r\n\r\n", file_header_idx) + 4
	var data_end_idx = -1
	for i in range(data_start_idx, request_data.size() - boundary_bytes.size()):
		var match_found = true
		for j in range(boundary_bytes.size()):
			if request_data[i + j] != boundary_bytes[j]:
				match_found = false
				break
		if match_found:
			data_end_idx = i - 2
			break
	if data_end_idx == -1:
		_send_response(peer, 400, "text/plain", "Error: Unknown end of file!")
		return
	var xml_bytes = request_data.slice(data_start_idx, data_end_idx)
	var full_path = upload_dir.path_join(filename)
	var file = FileAccess.open(full_path, FileAccess.WRITE)
	if file:
		file.store_buffer(xml_bytes)
		file.close()
		log_requested.emit.call_deferred("[WWW] (OK) File uploaded: " + full_path)
		var success_msg = "<b>Upload successfully!</b><br /><br />File<br /><br /><b>(OK)</b> " + filename + "<br /><br />added to GodotSauger!"
		_send_response(peer, 200, "text/html", success_msg)
	else:
		_send_response(peer, 500, "text/plain", "Konnte Datei nicht auf Server schreiben.")

func _send_response(peer: StreamPeerTCP, status_code: int, content_type: String, body: String) -> void:
	var status_text = "OK"
	if status_code == 400: status_text = "Bad Request"
	elif status_code == 405: status_text = "Method Not Allowed"
	elif status_code == 500: status_text = "Internal Server Error"
	var response = "HTTP/1.1 " + str(status_code) + " " + status_text + "\r\n"
	response += "Content-Type: " + content_type + "; charset=utf-8\r\n"
	response += "Content-Length: " + str(body.to_utf8_buffer().size()) + "\r\n"
	response += "Connection: close\r\n"
	response += "\r\n"
	response += body
	peer.put_data(response.to_utf8_buffer())
	'''

extends Node
class_name WWWServer

signal log_requested(text: String, color: String)

@export var port: int = 8080
@export var upload_dir: String = ""

var tcp_server: TCPServer = TCPServer.new()
var server_thread: Thread = Thread.new()
var is_running: bool = false

# NEU: Variablen für den Log-Stream
var log_clients: Array[StreamPeerTCP] = []
var log_queue: Array[String] = []
var queue_mutex: Mutex = Mutex.new()

func _ready() -> void:
	if not DirAccess.dir_exists_absolute(upload_dir):
		DirAccess.make_dir_recursive_absolute(upload_dir)
		log_requested.emit.call_deferred("[WWW] Path created: " + upload_dir)
	start_server()

func _exit_tree() -> void:
	stop_server()

func start_server() -> void:
	var error = tcp_server.listen(port)
	if error != OK:
		log_requested.emit.call_deferred("[WWW] Error creating webserver on port: " + str(port), "red")
		return
	is_running = true
	log_requested.emit.call_deferred("[WWW] Running on port: " + str(port), "orange")
	server_thread.start(Callable(self, "_thread_loop"))

func stop_server() -> void:
	is_running = false
	tcp_server.stop()
	if server_thread.is_started():
		server_thread.wait_to_finish()
	log_requested.emit.call_deferred("[WWW] Webserver stopped!", "orange")

# NEU: Funktion um Logs von der main.gd zu empfangen
func add_log_to_web(html_text: String) -> void:
	queue_mutex.lock()
	# SSE Format: Nachricht muss mit "data: " beginnen und "\n\n" enden
	log_queue.append("data: " + html_text + "\n\n")
	queue_mutex.unlock()

func _thread_loop() -> void:
	while is_running:
		# 1. Neue Verbindungen annehmen
		if tcp_server.is_connection_available():
			var peer: StreamPeerTCP = tcp_server.take_connection()
			_handle_client(peer)
		
		# 2. Bestehende Log-Streams füttern
		_process_log_streams()
		
		OS.delay_msec(10)

# NEU: Verteilt die Logs an alle Browser, die /logs offen haben
func _process_log_streams() -> void:
	queue_mutex.lock()
	var current_logs = log_queue.duplicate()
	log_queue.clear()
	queue_mutex.unlock()

	var disconnected_clients = []
	for client in log_clients:
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			disconnected_clients.append(client)
			continue
		
		for msg in current_logs:
			client.put_data(msg.to_utf8_buffer())
	
	for c in disconnected_clients:
		log_clients.erase(c)

func _handle_client(peer: StreamPeerTCP) -> void:
	var timeout = 5.0
	while peer.get_available_bytes() == 0 and timeout > 0:
		OS.delay_msec(50)
		timeout -= 0.05
	if peer.get_available_bytes() == 0:
		peer.disconnect_from_host()
		return
	var bytes = peer.get_partial_data(peer.get_available_bytes())
	var request_data: PackedByteArray = bytes[1]
	var request_string: String = request_data.get_string_from_utf8()
	if request_string.is_empty():
		peer.disconnect_from_host()
		return
	var lines = request_string.split("\r\n")
	if lines.size() == 0:
		peer.disconnect_from_host()
		return
	var request_line = lines[0]
	
	# NEU: Unterscheidung zwischen Seite, Log-Stream und Upload
	if request_line.begins_with("GET /logs"):
		_start_sse_stream(peer)
		# Hier KEIN disconnect, da die Verbindung für den Stream offen bleiben muss!
	elif request_line.begins_with("GET"):
		_send_html_page(peer)
		peer.disconnect_from_host()
	elif request_line.begins_with("POST"):
		_handle_file_upload(peer, request_string, request_data)
		peer.disconnect_from_host()
	else:
		_send_response(peer, 405, "text/plain", "Method Not Allowed")
		peer.disconnect_from_host()

# NEU: Initialisiert den Log-Stream für den Browser
func _start_sse_stream(peer: StreamPeerTCP) -> void:
	var header = "HTTP/1.1 200 OK\r\n"
	header += "Content-Type: text/event-stream\r\n"
	header += "Cache-Control: no-cache\r\n"
	header += "Connection: keep-alive\r\n"
	header += "Access-Control-Allow-Origin: *\r\n"
	header += "\r\n"
	peer.put_data(header.to_utf8_buffer())
	log_clients.append(peer)

func _send_html_page(peer: StreamPeerTCP) -> void:
	var html_resource = preload("res://webserver/index.gd")
	if html_resource:
		var html_text = html_resource.HTML
		_send_response(peer, 200, "text/html", html_text)
	else:
		_send_response(peer, 404, "text/plain", "Error: Script-Resource not found!")

func _handle_file_upload(peer: StreamPeerTCP, request_string: String, request_data: PackedByteArray) -> void:
	var boundary = ""
	var lines = request_string.split("\r\n")
	for line in lines:
		if line.begins_with("Content-Type: multipart/form-data; boundary="):
			boundary = line.split("boundary=")[1].strip_edges()
			break
	if boundary == "":
		_send_response(peer, 400, "text/plain", "Bad Request: No Boundary")
		return
	var boundary_bytes = ("--" + boundary).to_utf8_buffer()
	var filename = "unnamed.sfdl"
	var content_disposition = 'filename="'
	var filename_idx = request_string.find(content_disposition)
	if filename_idx != -1:
		var start = filename_idx + content_disposition.length()
		var end = request_string.find('"', start)
		filename = request_string.substr(start, end - start)
		filename = filename.get_file()
		if filename.is_empty(): filename = "unnamed.sfdl"
	var search_string = 'filename="' + filename + '"'
	var file_header_idx = request_string.find(search_string)
	if file_header_idx == -1:
		_send_response(peer, 400, "text/plain", "Dateiformat ungueltig")
		return
	var data_start_idx = request_string.find("\r\n\r\n", file_header_idx) + 4
	var data_end_idx = -1
	for i in range(data_start_idx, request_data.size() - boundary_bytes.size()):
		var match_found = true
		for j in range(boundary_bytes.size()):
			if request_data[i + j] != boundary_bytes[j]:
				match_found = false
				break
		if match_found:
			data_end_idx = i - 2
			break
	if data_end_idx == -1:
		_send_response(peer, 400, "text/plain", "Error: Unknown end of file!")
		return
	var xml_bytes = request_data.slice(data_start_idx, data_end_idx)
	var full_path = upload_dir.path_join(filename)
	var file = FileAccess.open(full_path, FileAccess.WRITE)
	if file:
		file.store_buffer(xml_bytes)
		file.close()
		log_requested.emit.call_deferred("[WWW] (OK) File uploaded: " + full_path)
		var success_msg = "<b>Upload successfully!</b><br /><br />File<br /><br /><b>(OK)</b> " + filename + "<br /><br />added to GodotSauger!"
		_send_response(peer, 200, "text/html", success_msg)
	else:
		_send_response(peer, 500, "text/plain", "Konnte Datei nicht auf Server schreiben.")

func _send_response(peer: StreamPeerTCP, status_code: int, content_type: String, body: String) -> void:
	var status_text = "OK"
	if status_code == 400: status_text = "Bad Request"
	elif status_code == 405: status_text = "Method Not Allowed"
	elif status_code == 500: status_text = "Internal Server Error"
	var response = "HTTP/1.1 " + str(status_code) + " " + status_text + "\r\n"
	response += "Content-Type: " + content_type + "; charset=utf-8\r\n"
	response += "Content-Length: " + str(body.to_utf8_buffer().size()) + "\r\n"
	response += "Connection: close\r\n"
	response += "\r\n"
	response += body
	peer.put_data(response.to_utf8_buffer())

	
