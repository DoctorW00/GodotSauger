extends Node

signal log_requested(text: String, color: String)
signal extraction_finished(success, output)

var re_part = RegEx.create_from_string(r"\.part([0-9]+)\.rar$")
var re_legacy_vol = RegEx.create_from_string(r"^[a-z][0-9]{2}$")

func _is_first_rar_volume(file_name: String) -> bool:
	var lower_name = file_name.to_lower()
	if lower_name.ends_with(".rar"):
		var match_part = re_part.search(lower_name)
		if match_part:
			return match_part.get_string(1).to_int() == 1
		return true
	return false
	
func _delete_archive_parts(first_volume_path: String):
	var base_dir = first_volume_path.get_base_dir()
	var file_name_only = first_volume_path.get_file()
	var name_stem = file_name_only.get_basename()
	if ".part" in name_stem:
		name_stem = name_stem.split(".part")[0]
	var dir = DirAccess.open(base_dir)
	if not dir: return
	dir.list_dir_begin()
	var current_item = dir.get_next()
	while current_item != "":
		if current_item.begins_with(name_stem):
			var ext = current_item.get_extension().to_lower()
			var is_rar = (ext == "rar")
			var is_vol = re_legacy_vol.search(ext) != null
			if is_rar or is_vol:
				dir.remove(current_item)
				log_requested.emit.call_deferred("[Extractor] Removing: " + current_item)
		current_item = dir.get_next()
	dir.list_dir_end()

func get_tool_type(tool_path: String):
	var file_name = tool_path.get_file().to_lower()
	if "7z" in file_name or "7zip" in file_name:
		return "7zip"
	elif "unrar" in file_name:
		return "UnRAR"
	return "Unknown"

func start_recursive_search_task(base_path: String, tool_path: String, delete_after: bool):
	var search_task = func():
		_search_step_recursive(base_path, tool_path, delete_after)
	WorkerThreadPool.add_task(search_task)

func _search_step_recursive(current_path: String, tool_path: String, delete_after: bool):
	var dir = DirAccess.open(current_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var full_path = current_path.path_join(file_name)
		if dir.current_is_dir():
			_search_step_recursive(full_path, tool_path, delete_after)
		else:
			if _is_first_rar_volume(file_name):
				log_requested.emit.call_deferred("[Extractor] Found-RAR: " + file_name, "yellow")
				start_async_extraction(tool_path, full_path, current_path, delete_after)
		file_name = dir.get_next()
	dir.list_dir_end()

func start_async_extraction(tool_path: String, archive: String, destination: String, delete_after: bool):
	var tool = get_tool_type(tool_path)
	if tool == "Unknown":
		log_requested.emit.call_deferred("[Extractor] Only 7zip and UnRAR supported!", "red")
		return
	var task = func():
		if tool == "7zip":
			_run_extraction_task_7zip(tool_path, archive, destination, delete_after)
		elif tool == "UnRAR":
			_run_extraction_task_unrar(tool_path, archive, destination, delete_after)
	WorkerThreadPool.add_task(task)

func _run_extraction_task_7zip(tool_path: String, archive_path: String, output_dir: String, delete_after: bool):
	log_requested.emit.call_deferred("[Extractor] (7zip) Extracting: " + archive_path)
	var output = []
	var exit_code = OS.execute(tool_path, ["x", archive_path, "-o" + output_dir, "-y"], output, true)
	var success = (exit_code == 0)
	if success and delete_after:
		_delete_archive_parts(archive_path)
	extraction_finished.emit.call_deferred(success, output)

func _run_extraction_task_unrar(tool_path: String, archive_path: String, output_dir: String, delete_after: bool):
	log_requested.emit.call_deferred("[Extractor] (UnRAR) Extracting: " + archive_path)
	if not DirAccess.dir_exists_absolute(output_dir):
		DirAccess.make_dir_recursive_absolute(output_dir)
	var output = []
	var args = ["x", "-o+", "-y", archive_path, output_dir]
	var exit_code = OS.execute(tool_path, args, output, true)
	var success = (exit_code == 0)
	if success and delete_after:
		_delete_archive_parts(archive_path)
	extraction_finished.emit.call_deferred(success, output)
