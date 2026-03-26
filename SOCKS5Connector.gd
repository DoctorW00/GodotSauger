class_name SOCKS5Connector
extends RefCounted

static func connect_via_proxy(socket: StreamPeerTCP, p_host: String, p_port: int, target_host: String, target_port: int, user: String = "", passw: String = "") -> Error:
	var err = socket.connect_to_host(p_host, p_port)
	if err != OK: return err
	var timeout = 5000
	while socket.get_status() == StreamPeerTCP.STATUS_CONNECTING and timeout > 0:
		socket.poll()
		OS.delay_msec(10)
		timeout -= 10
	if socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return ERR_CANT_CONNECT
	var methods = PackedByteArray([0x05])
	if user != "":
		methods.append(0x02)
		methods.append(0x00)
		methods.append(0x02)
	else:
		methods.append(0x01)
		methods.append(0x00)
	socket.put_data(methods)
	var res = _wait_and_get(socket, 2)
	if res.size() < 2 or res[0] != 0x05: 
		return ERR_CONNECTION_ERROR
	var selected_method = res[1]
	if selected_method == 0x02:
		if user == "": return ERR_UNCONFIGURED
		var auth_packet = PackedByteArray([0x01])
		auth_packet.append(user.length())
		auth_packet.append_array(user.to_utf8_buffer())
		auth_packet.append(passw.length())
		auth_packet.append_array(passw.to_utf8_buffer())
		socket.put_data(auth_packet)
		var auth_res = _wait_and_get(socket, 2)
		if auth_res.size() < 2 or auth_res[1] != 0x00:
			return ERR_UNAUTHORIZED
	elif selected_method == 0xFF:
		return ERR_CANT_CONNECT
	var req = PackedByteArray([0x05, 0x01, 0x00, 0x03])
	req.append(target_host.length())
	req.append_array(target_host.to_utf8_buffer())
	req.append(target_port >> 8)
	req.append(target_port & 0xFF)
	socket.put_data(req)
	var conn_res = _wait_and_get(socket, 10)
	if conn_res.size() < 2 or conn_res[1] != 0x00:
		return ERR_CANT_CONNECT
	return OK

static func _wait_and_get(socket: StreamPeerTCP, expected: int) -> PackedByteArray:
	var timeout = 5000
	while socket.get_available_bytes() < expected and timeout > 0:
		socket.poll()
		OS.delay_msec(10)
		timeout -= 10
	var data = socket.get_data(socket.get_available_bytes())
	return data[1] if data[0] == OK else PackedByteArray()
