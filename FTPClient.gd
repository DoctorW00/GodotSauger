extends Node

signal ftp_ready(items: Array)
signal download_started(file_name: String)
signal download_progress(file_name: String, current: int, total: int)
signal download_finished(file_name: String, success: bool)
signal ftp_status_message(msg: String)
signal log_requested(text: String, color: String)

var list_thread: Thread = Thread.new()
var download_thread: Thread = Thread.new()
var abort_all: bool = false

var control_socket: StreamPeerTCP = StreamPeerTCP.new()
var proxy_use = false
var proxy_host = ""
var proxy_port = 0
var proxy_user = ""
var proxy_pass = ""

func stop_all_downloads():
	abort_all = true
	log_requested.emit.call_deferred("[FTP] All downloads canceled!", "red")
	await get_tree().create_timer(0.5).timeout
	abort_all = false

func start_ftp_list(host: String, port: int, user: String, password: String, path: String = "/"):
	if list_thread.is_started():
		list_thread.wait_to_finish()
	# log_requested.emit.call_deferred("[FTP] (LIST) Start Session for: " + path)
	var args = {"host": host, "port": port, "user": user, "pass": password, "path": path}
	list_thread.start(_threaded_list_logic.bind(args))

func _threaded_list_logic(args: Dictionary):
	var l_socket = StreamPeerTCP.new()
	var err: Error
	if proxy_use:
		log_requested.emit.call_deferred("[FTP] (LIST) (Proxy) Using Socks5 Proxy: " + proxy_host + ":" + str(proxy_port))
		err = SOCKS5Connector.connect_via_proxy(
			l_socket,
			proxy_host,
			proxy_port,
			args.host,
			args.port,
			proxy_user,
			proxy_pass
		)
	else:
		err = l_socket.connect_to_host(args.host, args.port)
	if err != OK:
		log_requested.emit.call_deferred("[FTP] (LIST) Connection error: " + error_string(err), "red")
		ftp_status_message.emit.call_deferred("Connection error!")
		return
	while l_socket.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		l_socket.poll()
		OS.delay_msec(10)
	log_requested.emit.call_deferred("[FTP] (LIST) Connected. Login ... ")
	_wait_response(l_socket)
	_send_cmd(l_socket, "USER " + args.user)
	_wait_response(l_socket)
	_send_cmd(l_socket, "PASS " + args.pass)
	var res = _wait_response(l_socket)
	if res.begins_with("230"):
		log_requested.emit.call_deferred("[FTP] (LIST) 230 Login OK. CWD: " + args.path)
		_send_cmd(l_socket, "CWD " + args.path)
		var cwd_res = _wait_response(l_socket)
		if cwd_res.begins_with("250"):
			var items = _get_listing_internal(l_socket, args.host, args.path)
			log_requested.emit.call_deferred("[FTP] (LIST) Done. %d Elements found." % items.size(), "green")
			ftp_ready.emit.call_deferred(items)
		else:
			log_requested.emit.call_deferred("[FTP] (LIST) CWD Fehler: " + cwd_res, "red")
			ftp_status_message.emit.call_deferred("Pfad nicht gefunden!")
			ftp_ready.emit.call_deferred([])
	else:
		log_requested.emit.call_deferred("[FTP] (LIST) Login error: " + res, "red")
		ftp_status_message.emit.call_deferred("Login Error")
	close_any_socket(l_socket, "LIST", false)

func _get_listing_internal(ctrl_socket: StreamPeerTCP, host: String, current_path: String) -> Array:
	if current_path == "": current_path = "/"
	_send_cmd(ctrl_socket, "CWD " + current_path)
	_wait_response(ctrl_socket)
	_send_cmd(ctrl_socket, "PASV")
	var pasv_res = _wait_response(ctrl_socket)
	var data_port = parse_pasv_port(pasv_res)
	if data_port == -1: return []
	var d_socket = _open_data_connection_via_proxy(pasv_res, host)
	if d_socket == null:
		log_requested.emit.call_deferred("[FTP] (LIST) Data Connection failed!", "red")
		return []
	while d_socket.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		d_socket.poll()
		OS.delay_msec(5)
	var all_items = []
	if d_socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_send_cmd(ctrl_socket, "LIST")
		_wait_response(ctrl_socket)
		var raw = ""
		while true:
			d_socket.poll()
			var status = d_socket.get_status()
			if status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_ERROR:
				var av = d_socket.get_available_bytes()
				if av > 0:
					raw += d_socket.get_utf8_string(av)
			if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
				break
			OS.delay_msec(1)
		d_socket.disconnect_from_host()
		_wait_response(ctrl_socket)
		var current_level_items = parse_ftp_listing(raw)
		for item in current_level_items:
			if item.name == "." or item.name == "..":
				continue
			var full_path = current_path
			if not full_path.ends_with("/"): full_path += "/"
			full_path += item.name
			item["path"] = full_path
			all_items.append(item)
			if item.is_dir:
				log_requested.emit.call_deferred("[FTP] (LIST) Recursive path: " + full_path)
				var sub_items = _get_listing_internal(ctrl_socket, host, full_path)
				all_items.append_array(sub_items)
				_send_cmd(ctrl_socket, "CWD " + current_path)
				_wait_response(ctrl_socket)
	return all_items

func start_ftp_download(host: String, port: int, user: String, password: String, remote_file: String, local_file: String):
	if abort_all:
		download_finished.emit.call_deferred(remote_file, false)
		return
	var args = {
		"host": host, 
		"port": port, 
		"user": user, 
		"pass": password, 
		"remote": remote_file, 
		"local": local_file
	}
	WorkerThreadPool.add_task(_threaded_download_logic.bind(args))

func _threaded_download_logic(args: Dictionary):
	var thread_control = StreamPeerTCP.new()
	var err: Error
	if abort_all or not is_instance_valid(self): return
	if proxy_use:
		log_requested.emit.call_deferred("[FTP] (DL-Thread) Connecting using Proxy...", "magenta")
		err = SOCKS5Connector.connect_via_proxy(
			thread_control, 
			proxy_host,
			proxy_port, 
			args.host,
			args.port, 
			proxy_user,
			proxy_pass
		)
	else:
		err = thread_control.connect_to_host(args.host, args.port)
		var timeout = 5000
		while thread_control.get_status() == StreamPeerTCP.STATUS_CONNECTING and timeout > 0:
			if abort_all: 
				thread_control.disconnect_from_host()
				return
			thread_control.poll()
			OS.delay_msec(10)
			timeout -= 10		
	if err != OK or thread_control.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if is_instance_valid(self) and not abort_all:
			log_requested.emit.call_deferred("[FTP] (DL-Thread) Control Connection failed: " + error_string(err), "red")
			download_finished.emit.call_deferred(args.remote, false)
		return
	if abort_all or not is_instance_valid(self):
		thread_control.disconnect_from_host()
		return
	_wait_response(thread_control)
	_send_cmd(thread_control, "USER " + args.user)
	_wait_response(thread_control)
	_send_cmd(thread_control, "PASS " + args.pass)
	var login_res = _wait_response(thread_control)
	if not login_res.begins_with("230"):
		if is_instance_valid(self) and not abort_all:
			log_requested.emit.call_deferred("[FTP] (DL-Thread) Login failed: " + login_res, "red")
			download_finished.emit.call_deferred(args.remote, false)
		thread_control.disconnect_from_host()
		return
	if is_instance_valid(self) and not abort_all:
		_do_actual_download(thread_control, args.host, args.remote, args.local)
	if is_instance_valid(self) and not abort_all:
		close_any_socket(thread_control, "DL-CTRL", true)
	else:
		if is_instance_valid(thread_control):
			if thread_control.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				thread_control.put_data("QUIT\r\n".to_utf8_buffer())
				thread_control.poll()
			thread_control.disconnect_from_host()

func _do_actual_download(ctrl_socket: StreamPeerTCP, host: String, remote: String, local: String):
	if abort_all or not is_instance_valid(self):
		return
	var dir_path = local.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	if not is_instance_valid(self) or abort_all: return
	_send_cmd(ctrl_socket, "TYPE I")
	_wait_response(ctrl_socket)
	if not is_instance_valid(self) or abort_all: return
	_send_cmd(ctrl_socket, "SIZE " + remote)
	var size_res = _wait_response(ctrl_socket)
	var total = 0
	if size_res.begins_with("213"): 
		total = size_res.split(" ")[1].to_int()
	var current = 0
	if FileAccess.file_exists(local):
		var existing_file = FileAccess.open(local, FileAccess.READ)
		if existing_file:
			current = existing_file.get_length()
			existing_file.close()
			if current >= total and total > 0:
				if is_instance_valid(self) and not abort_all:
					log_requested.emit.call_deferred("[FTP] (DL) Already 100%: " + remote.get_file(), "green")
					download_progress.emit.call_deferred(remote, total, total)
					download_finished.emit.call_deferred(remote, true)
				return
	if not is_instance_valid(self) or abort_all: return
	_send_cmd(ctrl_socket, "PASV")
	var pasv_res = _wait_response(ctrl_socket)
	var d_socket: StreamPeerTCP
	if proxy_use:
		d_socket = _open_data_connection_via_proxy(pasv_res, host)
	else:
		var data_port = parse_pasv_port(pasv_res)
		d_socket = StreamPeerTCP.new()
		var err = d_socket.connect_to_host(host, data_port)
		if err != OK:
			if is_instance_valid(self): download_finished.emit.call_deferred(remote, false)
			return
		while d_socket.get_status() == StreamPeerTCP.STATUS_CONNECTING:
			if abort_all: break
			d_socket.poll()
			OS.delay_msec(5)
	if d_socket == null or d_socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if is_instance_valid(self) and not abort_all:
			log_requested.emit.call_deferred("[FTP] (DL) Data Connection failed!", "red")
			download_finished.emit.call_deferred(remote, false)
		return
	var is_resuming = false
	if current > 0:
		if is_instance_valid(self): _send_cmd(ctrl_socket, "REST " + str(current))
		var rest_res = _wait_response(ctrl_socket)
		if rest_res.begins_with("350"):
			is_resuming = true
			if is_instance_valid(self): log_requested.emit.call_deferred("[FTP] (DL) Resume at: " + str(current), "yellow")
		else:
			current = 0
	if is_instance_valid(self): _send_cmd(ctrl_socket, "RETR " + remote)
	_wait_response(ctrl_socket)
	var file : FileAccess
	if is_resuming:
		file = FileAccess.open(local, FileAccess.READ_WRITE)
		if file: file.seek_end()
	else:
		file = FileAccess.open(local, FileAccess.WRITE)
	if file == null:
		if is_instance_valid(self): log_requested.emit.call_deferred("[FTP] (DL) File Error", "red")
		if is_instance_valid(d_socket): d_socket.disconnect_from_host()
		if is_instance_valid(self): download_finished.emit.call_deferred(remote, false)
		return
	if is_instance_valid(self): download_started.emit.call_deferred(remote)
	while true:
		if abort_all or not is_instance_valid(self): break
		
		d_socket.poll()
		var status = d_socket.get_status()
		if status != StreamPeerTCP.STATUS_CONNECTED:
			break
		var av = d_socket.get_available_bytes()
		
		if av > 0:
			var result = d_socket.get_data(av)
			if result[0] == OK:
				file.store_buffer(result[1])
				current += result[1].size()
				if is_instance_valid(self): 
					download_progress.emit.call_deferred(remote, current, total)
		if status != StreamPeerTCP.STATUS_CONNECTED and av <= 0:
			break
		OS.delay_msec(1)
	file.close()
	if is_instance_valid(d_socket): d_socket.disconnect_from_host()
	if is_instance_valid(self) and not abort_all:
		log_requested.emit.call_deferred("[FTP] (DL) Done: " + remote.get_file(), "green")
		download_finished.emit.call_deferred(remote, true)
	elif is_instance_valid(self) and abort_all:
		download_finished.emit.call_deferred(remote, false)

func _send_cmd(s: StreamPeerTCP, cmd: String):
	s.put_data((cmd + "\r\n").to_utf8_buffer())

func _wait_response(s: StreamPeerTCP) -> String:
	var timeout = 3000
	while s.get_available_bytes() == 0 and timeout > 0:
		s.poll()
		OS.delay_msec(50)
		timeout -= 50
	var res = s.get_utf8_string(s.get_available_bytes()).strip_edges()
	# if res != "": print("Server: ", res)
	return res

func parse_ftp_listing(raw_data: String) -> Array:
	var items = []
	var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var regex_os = RegEx.new()
	regex_os.compile("^(\\d{2}-\\d{2}-\\d{2})\\s+(\\d{2}:\\d{2}[AP]M)\\s+(<DIR>|\\d+)\\s+(.*)$")
	for line in raw_data.split("\n"):
		line = line.strip_edges()
		if line == "" or (line.length() >= 3 and line.substr(0, 3).is_valid_int()):
			continue
		var res_win = regex_os.search(line)
		if res_win:
			var size_or_dir = res_win.get_string(3)
			var is_dir = size_or_dir == "<DIR>"
			var s = 0 if is_dir else size_or_dir.to_int()
			items.append({
				"name": res_win.get_string(4).strip_edges(),
				"size": s,
				"is_dir": is_dir,
				"size_human": "DIR" if is_dir else format_file_size(s),
				"status": 0
			})
			continue
		if line.begins_with("d") or line.begins_with("-") or line.begins_with("l"):
			var parts = []
			for p in line.split(" ", false):
				parts.append(p)
			if parts.size() >= 6:
				var date_index = -1
				for i in range(1, parts.size() - 2):
					if months.has(parts[i]):
						date_index = i
						break
				if date_index != -1:
					var name_start_index = date_index + 3
					var file_name = ""
					for i in range(name_start_index, parts.size()):
						file_name += parts[i] + (" " if i < parts.size() - 1 else "")
					var s = parts[date_index - 1].to_int()
					items.append({
						"name": file_name.strip_edges(),
						"size": s,
						"is_dir": line.begins_with("d"),
						"size_human": "DIR" if line.begins_with("d") else format_file_size(s),
						"status": 0
					})
					continue
		log_requested.emit.call_deferred("[FTP] (LIST) Unknown format: " + line)
	return items

func format_file_size(bytes: int) -> String:
	if bytes < 1024:
		return str(bytes) + " B"
	var units = ["KB", "MB", "GB", "TB", "PB"]
	var size = float(bytes)
	var unit_index = -1
	while size >= 1024 and unit_index < units.size() - 1:
		size /= 1024.0
		unit_index += 1
	return "%.2f %s" % [size, units[unit_index]]

func parse_pasv_port(response: String) -> int:
	var regex = RegEx.new()
	regex.compile("\\((\\d+,\\d+,\\d+,\\d+,(\\d+),(\\d+))\\)")
	var res = regex.search(response)
	return (res.get_string(2).to_int() * 256) + res.get_string(3).to_int() if res else 0

func _exit_tree():
	abort_all = true
	if list_thread.is_started():
		list_thread.wait_to_finish()
	if download_thread.is_started(): 
		download_thread.wait_to_finish()

func connect_to_proxy(ftp_host: String, ftp_port: int):
	var err = SOCKS5Connector.connect_via_proxy(
		control_socket,
		proxy_host,
		proxy_port,
		ftp_host,
		ftp_port,
		proxy_user,
		proxy_pass
	)
	if err == OK:
		log_requested.emit.call_deferred("[FTP] (Proxy) Connected!", "magenta")
	else:
		log_requested.emit.call_deferred("[FTP] (Proxy) Error: " + error_string(err), "red")

func close_any_socket(socket: StreamPeerTCP, _label: String, send_quit: bool = false):
	if not is_instance_valid(socket):
		return
	if socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		if send_quit:
			if not abort_all:
				socket.put_data("QUIT\r\n".to_utf8_buffer())
				socket.poll()
				OS.delay_msec(50)
		socket.disconnect_from_host()
		if is_instance_valid(self) and not abort_all:
			log_requested.emit.call_deferred("[FTP] (" + _label + ") Connection closed!", "magenta")

func _open_data_connection_via_proxy(pasv_response: String, target_ftp_host: String) -> StreamPeerTCP:
	var regex = RegEx.new()
	regex.compile("(\\d+),(\\d+)\\)") 
	var result = regex.search(pasv_response)
	if not result:
		log_requested.emit.call_deferred("[FTP] PASV Parse Error", "red")
		return null
	var p1 = int(result.get_string(1))
	var p2 = int(result.get_string(2))
	var target_data_port = (p1 * 256) + p2
	var d_socket = StreamPeerTCP.new()
	var err: Error
	if proxy_use:
		err = SOCKS5Connector.connect_via_proxy(
			d_socket, 
			proxy_host,
			proxy_port, 
			target_ftp_host,
			target_data_port, 
			proxy_user,
			proxy_pass
		)
	else:
		err = d_socket.connect_to_host(target_ftp_host, target_data_port)
	if err == OK:
		return d_socket
	else:
		log_requested.emit.call_deferred("[FTP] Data Proxy Error: " + error_string(err), "red")
		return null
		
func set_proxy_data(data: Dictionary):
	proxy_use = data.use
	proxy_host = data.host
	proxy_port = data.port
	proxy_user = data.user
	proxy_pass = data.pass
