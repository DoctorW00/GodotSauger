extends CheckButton

signal log_requested(text: String, color: String)
signal save_requested(settings_key: String, data: Variant)

func _ready():
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		visible = false
	var is_on = ProjectSettings.get_setting("display/window/energy_saving/keep_screen_on")
	button_pressed = is_on
	DisplayServer.screen_set_keep_on(is_on)

func _on_toggled(toggled_on: bool):
	DisplayServer.screen_set_keep_on(toggled_on)
	ProjectSettings.set_setting("display/window/energy_saving/keep_screen_on", toggled_on)
	if toggled_on:
		log_requested.emit("[INFO] Screen will stay -ON- !", "blue")
	else:
		log_requested.emit("[INFO] Screen will go dark again ...", "blue")
	save_requested.emit("keep_screen_on", toggled_on)
