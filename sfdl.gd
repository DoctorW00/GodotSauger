extends Node
class_name MeinXMLParser

func decrypt_aes_cbc(encrypted_b64: String, password_str: String) -> String:
	var data = Marshalls.base64_to_raw(encrypted_b64)
	if data.size() < 32: return ""
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(password_str.to_utf8_buffer())
	var key = ctx.finish()
	var iv = data.slice(0, 16)
	var payload = data.slice(16)
	var aes = AESContext.new()
	var err = aes.start(AESContext.MODE_CBC_DECRYPT, key, iv)
	if err != OK: return "Decrypt Error"
	var decrypted_buffer = aes.update(payload)
	aes.finish()
	if decrypted_buffer.size() > 0:
		var padding_len = decrypted_buffer[decrypted_buffer.size() - 1]
		if padding_len > 0 and padding_len <= 16:
			decrypted_buffer = decrypted_buffer.slice(0, decrypted_buffer.size() - padding_len)
	return decrypted_buffer.get_string_from_utf8().strip_edges()

func parse_sfdl_xml(path: String, password: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parser = XMLParser.new()
	var open_err = parser.open(path)
	if open_err != OK:
		return {}
	if parser.read() != OK:
		return {}
	var is_encrypted = false
	if parser.open(path) == OK:
		while parser.read() == OK:
			if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "Encrypted":
				parser.read()
				if parser.get_node_type() == XMLParser.NODE_TEXT:
					is_encrypted = (parser.get_node_data().strip_edges().to_lower() == "true")
				break
	if parser.open(path) != OK: return {}
	var result = {"ConnectionInfo": {}, "Packages": []}
	var current_node_name = ""
	var current_package = {}
	var crypto_fields = ["Description", "Uploader", "Host", "Username", "Password", "Packagename", "BulkFolderPath", "PackageName", "DefaultPath"]
	while parser.read() == OK:
		var node_type = parser.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			current_node_name = parser.get_node_name()
			if current_node_name == "SFDLPackage":
				current_package = {"Packagename": "", "BulkFolderList": []}
		elif node_type == XMLParser.NODE_TEXT:
			var text = parser.get_node_data().strip_edges()
			if text == "": continue
			# decrypt if <Encrypted>true</Encrypted>
			if is_encrypted and current_node_name in crypto_fields:
				text = decrypt_aes_cbc(text, password)
			if current_node_name in ["Description", "Uploader", "SFDLFileVersion", "Encrypted", "MaxDownloadThreads"]:
				result[current_node_name] = text
			elif current_node_name in ["Host", "Port", "Username", "Password", "DefaultPath"]:
				result["ConnectionInfo"][current_node_name] = text
			elif current_node_name == "Packagename":
				current_package["Packagename"] = text
			elif current_node_name == "BulkFolderPath":
				current_package["BulkFolderList"].append(text)
			elif current_node_name == "PackageName":
				pass
		elif node_type == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "SFDLPackage":
				result["Packages"].append(current_package.duplicate())
	return result
