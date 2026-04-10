extends Node3D

var gs_version = str(ProjectSettings.get_setting("application/config/version"))

var video_player : VideoStreamPlayer

const HttpServer = preload("res://WebServer.gd")
var web_server: Node

@onready var anim_player: AnimationPlayer = $hero_dance/AnimationPlayer
@onready var skeleton: Skeleton3D = $hero_dance/Armature/Skeleton3D

@onready var timer = $Timer
@onready var music_player = $MusicPlayer
@onready var play_sound = $PlaySounds
const ICON_ON = preload("res://icons/audio_on.png")
const ICON_OFF = preload("res://icons/audio_off.png")
@onready var btn_music = $Control/VBoxContainer/HBoxContainer2/Music
@onready var btn_settings = $Control/VBoxContainer/HBoxContainer2/Settings
@onready var btn_open_download_path = $Control/VBoxContainer/HBoxContainer/OpenDownloadPath

const VisualizerClass = preload("res://MusicVisualizer.gd")
var visualizer

@onready var main_ui = $Control
var main_ui_original_pos: Vector2
@onready var settings_ui = $ControlSettings
@onready var xrel_ui = $ControlWeb
@onready var cam = $Camera3D
@onready var tree = $Control/VBoxContainer/Tree
var bg_style = StyleBoxFlat.new()
var fill_style = StyleBoxFlat.new()
var error_style = StyleBoxFlat.new()
var fill_texture = GradientTexture2D.new()
var fill_style_gradient = StyleBoxTexture.new()
@onready var xrel_tree = $ControlWeb/VBoxContainer/xRELTree
@onready var xrel_error = $ControlWeb/VBoxContainer/MarginContainer/xRELError
@onready var log_box = $Control/VBoxContainer/LogBox
@onready var btn_open_sfdl = $Control/VBoxContainer/HBoxContainer/OpenSFDL
@onready var btn_start_download = $Control/VBoxContainer/HBoxContainer/StartDownload
@onready var path_edit = $Control/VBoxContainer/HBoxContainer2/PathEdit
@onready var download_title = $Control/VBoxContainer/HBoxContainer3/DownloadTitle
@onready var download_title_progress = $Control/VBoxContainer/HBoxContainer3/DownloadTitleProgress
@onready var download_title_info = $Control/VBoxContainer/HBoxContainer4/DownloadTitleInfo

var settings_fullscreen = false
var settings_allsoundoff = false
var settings_remove_archives = false
var settings_extractor_path = ""
var settings_use_extractor = false

var settings_webserver_run = false
var settings_webserver_port = 8080

var settings_proxy_use = false
var settings_proxy_host = ""
var settings_proxy_port = 0
var settings_proxy_user = ""
var settings_proxy_pass = ""

var settings_auto_download = false
var settings_auto_shutdown_pc = false
var settings_auto_sfdl_path = ""
var settings_auto_refresh_time = 30.0
@onready var auto_sfdl_timer = $TimerAutoDownloads

var path_dialog : FileDialog
var quit_dialog : ConfirmationDialog
var mouse_particles : GPUParticles2D

const SAVE_PATH = "user://GodotSauger.cfg"

var file_items = {}
var file_progress_bytes = {}
var sfdl_data = {}
var local_download_destination = ""
var sfdl_password = "mlcboard.com"
var sfdl_description = ""
var sfdl_uploader = ""
var max_concurrent_downloads = 3
var active_downloads = 0
var download_size = 0
var download_total_bytes = 0
var dowloads_canceled = false
var download_start_timestamp = 0
var download_stop_timestamp = 0
var download_seconds = 0
var download_errors = 0
var download_job_counter = 0

var last_track_index : int = -1

var last_check_time = 0.0
var last_check_bytes = 0
var current_speed_bytes_per_sec = 0.0
var speed_update_interval = 1.0
var time_accumulator = 0.0

var shutdown_dialog : ConfirmationDialog
var countdown_timer : Timer
var remaining_seconds : int = 30

var playlist : Array[String] = [
	"res://music/die-nudel.mp3",
	"res://music/unfug.mp3",
	"res://music/die-sache.mp3",
	"res://music/die-shout-box.mp3",
	"res://music/schwein-im-doener.mp3",
	"res://music/der-rueckenkratzer.mp3",
	"res://music/godot-sauger.mp3",
	"res://music/so-stirbt-man.mp3",
	"res://music/der-geier.mp3"
]

var randsounds : Array[AudioStream] = [
	preload("res://sounds/random_collection.mp3"),
	preload("res://sounds/random_cool.mp3"),
	preload("res://sounds/random_grafsauger.mp3"),
	preload("res://sounds/random_hard_sounger.mp3"),
	preload("res://sounds/random_nobugs.mp3"),
	preload("res://sounds/random_sexy.mp3"),
	preload("res://sounds/random_unfug.mp3"),
	preload("res://sounds/random_shotgun.mp3"),
	preload("res://sounds/random_hdd.mp3")
]

func _ready():
	var args = OS.get_cmdline_args()
	if args.size() > 0:
		for arg in args:
			if arg.get_extension().to_lower() == "sfdl":
				_on_sfdl_file_selected(arg)
				break
	print_welcome_banner()
	get_tree().get_root().files_dropped.connect(_on_files_dropped)
	load_window_settings()
	shutdown_dialog = ConfirmationDialog.new()
	add_child(shutdown_dialog)
	shutdown_dialog.title = "PC Shutdown"
	shutdown_dialog.ok_button_text = "Shutdown Now"
	shutdown_dialog.cancel_button_text = "Cancel"
	shutdown_dialog.confirmed.connect(_on_shutdown_confirmed)
	shutdown_dialog.canceled.connect(_on_shutdown_cancelled)
	setup_msaa_button()
	main_ui.visible = false
	btn_settings.expand_icon = true
	btn_settings.custom_minimum_size = Vector2(32, 32)
	btn_music.expand_icon = true
	btn_music.custom_minimum_size = Vector2(32, 24)
	btn_music.icon = ICON_ON
	btn_open_download_path.disabled = true
	timer.timeout.connect(_on_timer_timeout)
	start_random_timer()
	auto_sfdl_timer.timeout.connect(_on_auto_timer_timeout)
	download_title.bbcode_enabled = true
	download_title_info.bbcode_enabled = true
	music_player.bus = "Music"
	visualizer = VisualizerClass.new()
	visualizer.bar_count = 32
	add_child(visualizer)
	move_child(visualizer, 0)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.8, 0.8, 0.8) 
	style.set_corner_radius_all(4)
	btn_music.add_theme_stylebox_override("normal", style)
	var style_hover = style.duplicate()
	style_hover.bg_color = Color(0.9, 0.9, 0.9)
	btn_music.add_theme_stylebox_override("hover", style_hover)
	video_player = VideoStreamPlayer.new()
	get_viewport().add_child.call_deferred(video_player)
	video_player.volume = false
	video_player.expand = true
	video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	var stream = VideoStreamTheora.new()
	stream.file = "res://godotsauger.ogv"
	video_player.stream = stream
	video_player.finished.connect(_start_main_app)
	video_player.z_index = 999
	video_player.top_level = true
	await get_tree().process_frame
	video_player.play()
	await get_tree().process_frame
	get_tree().set_auto_accept_quit(false)
	$Control/VBoxContainer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$Control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_ui.offset_left = 10
	main_ui.offset_top = 10
	main_ui.offset_right = -10
	main_ui.offset_bottom = -5
	main_ui_original_pos = main_ui.position
	settings_ui.offset_left = 10
	settings_ui.offset_top = 10
	settings_ui.offset_right = -10
	settings_ui.offset_bottom = -10
	settings_ui.modulate.a = 0.9
	xrel_ui.offset_left = 10
	xrel_ui.offset_top = 10
	xrel_ui.offset_right = -10
	xrel_ui.offset_bottom = -10
	xrel_ui.modulate.a = 0.9
	xrel_error.visible = false
	quit_dialog = ConfirmationDialog.new()
	quit_dialog.title = "Quit Godot Sauger?"
	quit_dialog.dialog_text = "There are active downloads! Really quit now?"
	quit_dialog.ok_button_text = "Yep!"
	quit_dialog.cancel_button_text = "Nope!"
	quit_dialog.confirmed.connect(_cleanup_and_quit)
	quit_dialog.canceled.connect(_on_quit_dialog_canceled)
	add_child(quit_dialog)
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err == OK:
		if config.has_section_key("Settings", "download_path"):
			local_download_destination = config.get_value("Settings", "download_path")
			add_log("Loaded saved destination: " + local_download_destination, "gray")
		else:
			local_download_destination = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
			if local_download_destination == "":
				local_download_destination = OS.get_user_data_dir()
			add_log("Set default destination path: " + local_download_destination, "gray")
		
		if config.has_section_key("Settings", "settings_fullscreen"):
			settings_fullscreen = config.get_value("Settings", "settings_fullscreen")
			if settings_fullscreen:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/Fullscreen.button_pressed = true
			else:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/Fullscreen.button_pressed = false
		
		if config.has_section_key("Settings", "settings_allsoundoff"):
			settings_allsoundoff = config.get_value("Settings", "settings_allsoundoff")
			if settings_allsoundoff:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/AllSoundOff.button_pressed = true
				timer.stop()
			else:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/AllSoundOff.button_pressed = false
				
		if config.has_section_key("Settings", "webserver_port"):
			settings_webserver_port = config.get_value("Settings", "webserver_port")
			if settings_webserver_port is String:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/HBoxContainer/WebserverPort.value = settings_webserver_port.to_int()
			else:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/HBoxContainer/WebserverPort.value = int(settings_webserver_port)
		
		if config.has_section_key("Settings", "webserver_run"):
			settings_webserver_run = config.get_value("Settings", "webserver_run")
			if settings_webserver_run:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/WebserverButton.button_pressed = true
			else:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/WebserverButton.button_pressed = false
		
		if config.has_section_key("Settings", "extractor_remote_archives"):
			settings_remove_archives = config.get_value("Settings", "extractor_remote_archives")
			if settings_remove_archives:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/RemoveArchives.button_pressed = true
			else:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/RemoveArchives.button_pressed = false
		
		if config.has_section_key("Settings", "extractor_path"):
			settings_extractor_path = config.get_value("Settings", "extractor_path")
			$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer2/ExtractorLocation.text = settings_extractor_path
		
		if config.has_section_key("Settings", "extractor_use"):
			settings_use_extractor = config.get_value("Settings", "extractor_use")
			if settings_use_extractor:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/ExtractorUse.button_pressed = true
			else:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/ExtractorUse.button_pressed = false
		
		if config.has_section_key("Settings", "msaa_val"):
			var msaa_val = config.get_value("Settings", "msaa_level", 0)
			get_viewport().msaa_3d = msaa_val
			get_viewport().msaa_2d = msaa_val
			$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer/MSAAButton.selected = msaa_val
		
		if config.has_section_key("Settings", "fxaa_enabled"):
			var fxaa_on = config.get_value("Settings", "fxaa_enabled", false)
			if fxaa_on:
				get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			else:
				get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/FXAAButton.button_pressed = fxaa_on
		
		if config.has_section_key("Settings", "taa_enabled"):
			var taa_on = config.get_value("Settings", "taa_enabled", false)
			get_viewport().use_taa = taa_on
			$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/TAAButton.button_pressed = taa_on
			check_render_compatibility()
			
		if config.has_section_key("Settings", "proxy_use"):
			settings_proxy_use = config.get_value("Settings", "proxy_use")
			if settings_proxy_use:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/UseProxyButton.button_pressed = true
			else:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/UseProxyButton.button_pressed = false
		
		if config.has_section_key("Settings", "proxy_host"):
			settings_proxy_host = config.get_value("Settings", "proxy_host")
			if settings_proxy_host:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer3/ProxyHost.text = settings_proxy_host
				
		if config.has_section_key("Settings", "proxy_port"):
			settings_proxy_port = config.get_value("Settings", "proxy_port")
			if settings_proxy_port is String:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer4/ProxyPort.value = settings_proxy_port.to_int()
			else:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer4/ProxyPort.value = int(settings_proxy_port)
				
		if config.has_section_key("Settings", "proxy_user"):
			settings_proxy_user = config.get_value("Settings", "proxy_user")
			if settings_proxy_user:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer5/ProxyUser.text = settings_proxy_user
				
		if config.has_section_key("Settings", "proxy_pass"):
			settings_proxy_pass = config.get_value("Settings", "proxy_pass")
			if settings_proxy_pass:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer6/ProxyPass.text = settings_proxy_pass
		
		var proxy_data = {
			"use": settings_proxy_use,
			"host": settings_proxy_host,
			"port": settings_proxy_port,
			"user": settings_proxy_user,
			"pass": settings_proxy_pass
		}
		FtpClient.set_proxy_data(proxy_data)
		
		if config.has_section_key("Settings", "auto_download"):
			settings_auto_download = config.get_value("Settings", "auto_download")
			if settings_auto_download:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/AutoDownloadButton.button_pressed = true
			else:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/AutoDownloadButton.button_pressed = false
				
		if config.has_section_key("Settings", "auto_shutdown_pc"):
			settings_auto_shutdown_pc = config.get_value("Settings", "auto_shutdown_pc")
			if settings_auto_shutdown_pc:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/AutoShutdownPCButton.button_pressed = true
			else:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/AutoShutdownPCButton.button_pressed = false
		
		if config.has_section_key("Settings", "auto_sfdl_path"):
			settings_auto_sfdl_path = config.get_value("Settings", "auto_sfdl_path")
			if settings_auto_sfdl_path:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer7/AutoDownloadPath.text = settings_auto_sfdl_path
		else:
			settings_auto_sfdl_path = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
			if settings_auto_sfdl_path == "":
				settings_auto_sfdl_path = OS.get_user_data_dir()
			$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer7/AutoDownloadPath.text = settings_auto_sfdl_path
				
		if config.has_section_key("Settings", "auto_refresh_time"):
			settings_auto_refresh_time = config.get_value("Settings", "auto_refresh_time")
			if settings_auto_refresh_time is String:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer8/AutoTimer.value = settings_auto_refresh_time.to_int()
			else:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer8/AutoTimer.value = int(settings_auto_refresh_time)
		
		if config.has_section_key("Settings", "keep_screen_on"):
			var is_keep_screen_on = config.get_value("Settings", "keep_screen_on")
			if is_keep_screen_on:
				$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/MobileKeepScreenOn.button_pressed = true
		
	else:
		local_download_destination = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		if local_download_destination == "":
			local_download_destination = OS.get_user_data_dir()
	
	if settings_allsoundoff == false:
		play_sound.stream = load("res://sounds/intro_welcome.mp3")
		play_sound.play()
	
	if path_edit:
		path_edit.text = local_download_destination
	log_box.custom_minimum_size = Vector2(400, 200)
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.selection_enabled = true
	add_log("GodotSauger (" + gs_version + ") ready for Unfug!", "yellow")
	btn_start_download.disabled = true
	$Control/VBoxContainer/HBoxContainer3.visible = false
	$Control/VBoxContainer/HBoxContainer4.visible = false
	bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 1.0)
	bg_style.set_border_width_all(1)
	bg_style.border_color = Color(0.3, 0.3, 0.3)
	bg_style.set_corner_radius_all(6)
	fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.2, 0.7, 0.2)
	fill_style.set_corner_radius_all(6)
	fill_style.border_width_top = 2
	fill_style.border_color = Color(0.4, 0.9, 0.4)
	error_style = StyleBoxFlat.new()
	error_style.bg_color = Color(0.8, 0.2, 0.2)
	error_style.set_corner_radius_all(6)
	error_style.border_width_top = 2
	error_style.border_color = Color(1.0, 0.4, 0.4)
	tree.columns = 4
	tree.draw.connect(_on_tree_draw)
	tree.set_column_title(0, "Name")
	tree.set_column_title(1, "Size")
	tree.set_column_title(2, "Progress")
	tree.set_column_title(3, "Status")
	tree.column_titles_visible = true
	tree.set_column_expand(0, true)
	tree.set_column_clip_content(0, true)
	tree.set_column_expand(1, false)
	tree.set_column_expand(2, false)
	tree.set_column_expand(3, false)
	tree.set_column_custom_minimum_width(1, 110)
	tree.set_column_custom_minimum_width(2, 210)
	tree.set_column_custom_minimum_width(3, 100)
	tree.set_column_title_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
	xrel_tree.columns = 1
	xrel_tree.set_column_title(0, "Release")
	xrel_tree.column_titles_visible = false
	mouse_particles = GPUParticles2D.new()
	add_child(mouse_particles)
	mouse_particles.amount = 150
	mouse_particles.lifetime = 0.8
	mouse_particles.explosiveness = 0.0
	mouse_particles.randomness = 0.5
	mouse_particles.fixed_fps = 0
	var fill_tex = GradientTexture2D.new()
	var fill_grad = Gradient.new()
	fill_grad.set_color(0, Color(1, 1, 1, 1))
	fill_grad.set_color(1, Color(1, 1, 1, 0))
	fill_tex.gradient = fill_grad
	fill_tex.fill = GradientTexture2D.FILL_RADIAL
	fill_tex.fill_from = Vector2(0.5, 0.5)
	fill_tex.fill_to = Vector2(0.8, 0.8)
	fill_tex.width = 3
	fill_tex.height = 3
	mouse_particles.texture = fill_tex
	var mat = ParticleProcessMaterial.new()
	mat.gravity = Vector3(0, -100, 0) 
	mat.direction = Vector3(0, -1, 0)
	mat.scale_min = 3.0
	mat.scale_max = 10.0
	mat.spread = 50.0
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 35.0
	var grad_tex = GradientTexture1D.new()
	var grad = Gradient.new()
	grad.set_color(0, Color(1, 1, 0, 1))
	grad.set_color(1, Color(1, 0, 0, 0))
	grad.offsets = PackedFloat32Array([0.2, 1.0])
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex
	var curve_tex = CurveTexture.new()
	var curve = Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	curve_tex.curve = curve
	mat.scale_curve = curve_tex
	mouse_particles.process_material = mat
	mouse_particles.top_level = true
	mouse_particles.z_index = 100
	music_player.finished.connect(_play_random_song)
	$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/MobileKeepScreenOn.log_requested.connect(add_log)
	$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/MobileKeepScreenOn.save_requested.connect(save_settings)
	FtpClient.ftp_status_message.connect(_on_ftp_status_msg)
	FtpClient.ftp_ready.connect(_on_ftp_list_received)
	FtpClient.download_started.connect(_on_ftp_started)
	FtpClient.download_progress.connect(_on_ftp_progress)
	FtpClient.download_finished.connect(_on_ftp_finished)
	FtpClient.log_requested.connect(add_log)
	Extractor.log_requested.connect(add_log)
	Extractor.extraction_finished.connect(_on_extractor_finished)
	_on_refresh_pressed() # reset files list
	_on_auto_timer_timeout() # auto downloads
	var mesh_node = $hero_dance/Armature/Skeleton3D/char1
	if mesh_node and mesh_node is MeshInstance3D:
		var old_mat = mesh_node.get_active_material(0)
		var new_mat = StandardMaterial3D.new()
		if old_mat:
			new_mat.albedo_texture = old_mat.get("albedo_texture")
		mesh_node.material_override = new_mat

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
	if video_player == null:
		return
	if video_player.is_playing():
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		var is_keyboard_skip = event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")
		var is_mouse_skip = event is InputEventMouseButton and event.pressed
		if is_keyboard_skip or is_mouse_skip:
			video_player.stop()
			_start_main_app()

func _notification(what):
	if what == NOTIFICATION_APPLICATION_RESUMED:
		if OS.get_name() == "Android":
			if not OS.get_granted_permissions().has("android.permission.WRITE_EXTERNAL_STORAGE"):
				add_log("[Android] Need write premission!", "red")
				var permissions = OS.get_granted_permissions()
				add_log("[Android] Premissions: " + permissions, "magenta")
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		var current_size = DisplayServer.window_get_size()
		var current_pos = DisplayServer.window_get_position()
		save_settings("window_width", current_size.x)
		save_settings("window_height", current_size.y)
		save_settings("window_pos_x", current_pos.x)
		save_settings("window_pos_y", current_pos.y)
		if active_downloads <= 0:
			_cleanup_and_quit()
		else:
			quit_dialog.popup_centered()
			quit_dialog.grab_focus()

func _start_main_app():
	if main_ui.visible: 
		return
	if video_player:
		video_player.queue_free()
	if settings_allsoundoff == false:
		_play_random_song()
		start_dance()
	else:
		btn_music.icon = ICON_OFF
	main_ui.visible = true
	main_ui.modulate.a = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var final_pos = main_ui.position
	main_ui.position.y += 700
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(main_ui, "position:y", final_pos.y, 1.2)
	tween.tween_property(main_ui, "modulate:a", 0.9, 1.0)
	tween.set_parallel(false)
	tween.tween_callback(func(): mouse_particles.emitting = true)
	if OS.get_name() == "Android":
		OS.request_permissions()
	if settings_allsoundoff == false:
		play_sound.stream = load("res://sounds/event_ready.mp3")
		play_sound.play()

func _process(_delta):
	var m_pos = get_viewport().get_mouse_position()
	if mouse_particles:
		mouse_particles.global_position = m_pos
	if cam and has_node("OmniLight3D"):
		var light = get_node("OmniLight3D")
		var target_3d_pos = cam.project_position(m_pos, 2.0)
		light.global_position = target_3d_pos
	time_accumulator += _delta
	if time_accumulator >= speed_update_interval:
		var current_total_bytes = 0
		for val in file_progress_bytes.values():
			current_total_bytes += val
		var bytes_since_last = current_total_bytes - last_check_bytes
		current_speed_bytes_per_sec = bytes_since_last / time_accumulator
		last_check_bytes = current_total_bytes
		tree.queue_redraw()
		time_accumulator = 0.0

func _on_tree_draw():
	var root = tree.get_root()
	if not root: return
	var font = tree.get_theme_font("font")
	var font_size = tree.get_theme_font_size("font_size")
	var current = root.get_first_child()
	while current:
		var rect = tree.get_item_area_rect(current, 2)
		if rect.size.y > 0:
			var bar_rect = rect.grow(-3)
			var progress = current.get_metadata(2)
			if progress is float or progress is int:
				tree.draw_style_box(bg_style, bar_rect)
				if progress > 0:
					var fill_width = bar_rect.size.x * (clamp(progress, 0, 100) / 100.0)
					var fill_rect = Rect2(bar_rect.position, Vector2(fill_width, bar_rect.size.y))
					var status = current.get_text(3)
					if status == "Error":
						tree.draw_style_box(error_style, fill_rect)
					else:
						tree.draw_style_box(fill_style, fill_rect)
				var text = "%.2f%%" % progress
				var text_pos = bar_rect.position + Vector2(0, bar_rect.size.y * 0.8)
				tree.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, bar_rect.size.x, font_size)
		current = current.get_next_visible()

func update_file_progress(file_name: String, current_bytes: float, total_bytes: float):
	if file_items.has(file_name):
		var tree_item = file_items[file_name]
		var percent = 0.0
		if total_bytes > 0:
			percent = (current_bytes / total_bytes) * 100.0
		tree_item.set_metadata(2, percent)
		tree.queue_redraw()

func format_seconds(seconds: float) -> String:
	if seconds <= 0:
		return "0s"
	var t = int(seconds)
	var s = t % 60
	@warning_ignore("integer_division")
	var m = (t / 60) % 60
	@warning_ignore("integer_division")
	var h = (t / 3600) % 24
	@warning_ignore("integer_division")
	var d = t / 86400
	if d > 0:
		return "%dd %02dh:%02dm:%02ds" % [d, h, m, s]
	if h > 0:
		return "%dh:%02dm:%02ds" % [h, m, s]
	if m > 0:
		return "%02dm:%02ds" % [m, s]
	return "%ds" % [s]

func start_random_timer():
	var wait_time = randf_range(15.0, 60.0)
	timer.start(wait_time)

func _on_timer_timeout():
	if play_sound.playing:
		await play_sound.finished
	play_sound.stream = randsounds.pick_random()
	play_sound.play()
	start_random_timer()

func print_welcome_banner():
	var cyan = "\u001b[36m"
	var reset = "\u001b[0m"
	var banner = """
%s                                                                         
  ▄▄▄▄▄▄▄           ▄▄              ▄▄▄▄▄▄▄                               
 ███▀▀▀▀▀           ██        ██   █████▀▀▀                               
 ███       ▄███▄ ▄████ ▄███▄ ▀██▀▀  ▀████▄   ▀▀█▄ ██ ██ ▄████ ▄█▀█▄ ████▄ 
 ███  ███▀ ██ ██ ██ ██ ██ ██  ██      ▀████ ▄█▀██ ██ ██ ██ ██ ██▄█▀ ██ ▀▀ 
 ▀██████▀  ▀███▀ ▀████ ▀███▀  ██   ███████▀ ▀█▄██ ▀██▀█ ▀████ ▀█▄▄▄ ██    
                                                           ██             
                                                         ▀▀▀              %s
	""" % [cyan, reset]

	print(banner)
	print("")


func add_log(text: String, color: String = "white"):
	var time = Time.get_time_dict_from_system()
	var timestamp = "[%02d:%02d:%02d] " % [time.hour, time.minute, time.second]
	log_box.append_text("[color=gray]" + timestamp + "[/color][color=" + color + "]" + text + "[/color]\n")
	if is_instance_valid(web_server) and web_server.is_running:
		var html_log = '<span style="color: gray;">%s</span><span style="color: %s;">%s</span>' % [timestamp, color, text]
		web_server.add_log_to_web(html_log)
	var ansi_color = "\u001b[0m"
	match color:
		"red": ansi_color = "\u001b[31m"
		"green": ansi_color = "\u001b[32m"
		"orange", "yellow": ansi_color = "\u001b[33m"
		"blue": ansi_color = "\u001b[34m"
		"gray": ansi_color = "\u001b[90m"
	print("\u001b[90m" + timestamp + "\u001b[0m" + ansi_color + text + "\u001b[0m")
	if color == "red":
		if settings_allsoundoff == false:
			if play_sound.playing:
				await play_sound.finished
			play_sound.stream = load("res://sounds/event_error.mp3")
			play_sound.play()

func _on_refresh_pressed():
	tree.clear()
	file_items.clear()
	var _root = tree.create_item()

func _play_random_song():
	if playlist.is_empty():
		return
	if playlist.size() == 1:
		_start_track(0)
		return
	var random_index = last_track_index
	while random_index == last_track_index:
		random_index = randi() % playlist.size()
	last_track_index = random_index
	_start_track(random_index)
	
func _start_track(index):
	var track_path = playlist[index]
	add_log("🎵 Playing: " + track_path.get_file(), "pink")
	var stream = load(track_path)
	music_player.stream = stream
	music_player.play()

func start_ftp_index(_host: String, _port: int, _user: String, _pass: String, _path: String, _description: String):
	if _description.strip_edges().is_empty():
		add_log("(start_ftp_index): Description is empty!", "red")
		return
	add_log("Get FTP index for: " + _description)
	if _host.strip_edges().is_empty():
		add_log("(start_ftp_index): Host is empty!", "red")
		return
	if _port < 1 or _port > 65535:
		add_log("(start_ftp_index): Port is not valid!", "red")
		return
	if _path.strip_edges().is_empty():
		_path = "/"
	$Control/VBoxContainer/HBoxContainer3.visible = true
	$Control/VBoxContainer/HBoxContainer4.visible = true
	download_title.visible = true
	download_title_progress.visible = true
	download_title.text = "[b]" + sfdl_description + "[/b]"
	download_title_progress.value = 0.0
	active_downloads = 1
	_on_refresh_pressed()
	download_size = 0
	download_total_bytes = 0
	current_speed_bytes_per_sec = 0.0
	toggle_proxy_settings()
	FtpClient.start_ftp_list(
		_host,
		_port,
		_user,
		_pass,
		_path
	)

func _on_ftp_status_msg(_msg: String):
	active_downloads = 0

func _on_ftp_list_received(items: Array):
	active_downloads = 0
	toggle_proxy_settings()
	file_items.clear()
	file_progress_bytes.clear()
	var root = tree.get_root()
	if not root:
		root = tree.create_item()
	download_size = 0
	if not items.is_empty():
		for item in items:
			if item.get("is_dir", false):
				continue
			var tree_item = tree.create_item(root)
			download_size += item.size
			tree_item.set_text(1, item.size_human)
			tree_item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
			tree_item.set_cell_mode(2, TreeItem.CELL_MODE_CUSTOM)
			tree_item.set_metadata(2, 0.0)
			tree_item.set_text(3, "Ready")
			tree_item.set_metadata(0, item)
			file_items[item.name] = tree_item
			file_progress_bytes[item.name] = 0
			var relative_sub_path = compare_paths(item.path)
			tree_item.set_text(0, relative_sub_path)
			var dest_file = local_download_destination.path_join(sfdl_description).path_join(relative_sub_path)
			is_local_file_complete(dest_file, item.path, item.size)
		download_title.text = "[b]" + sfdl_description + "[/b]"
		download_title_info.text = "Size: [color=green]" + FtpClient.format_file_size(download_size) + "[/color]"
		btn_start_download.disabled = false
		if settings_allsoundoff == false:
			play_sound.stream = load("res://sounds/event_ready4donwload.mp3")
			play_sound.play()
		if settings_auto_download:
			_on_start_download_pressed()
	else:
		$Control/VBoxContainer/HBoxContainer3.visible = false
		$Control/VBoxContainer/HBoxContainer4.visible = false

func is_local_file_complete(local: String, path: String, total: int):	
	var current = 0
	if FileAccess.file_exists(local):
		var existing_file = FileAccess.open(local, FileAccess.READ)
		if existing_file:
			current = existing_file.get_length()
			existing_file.close()
			if current > 0 and total > 0:
				_on_ftp_progress(path, current, total)       

func _on_ftp_started(file_name: String):
	var tree_item = find_item_by_path(tree.get_root(), file_name)
	tree_item.set_text(3, "Loading...")
	var data = tree_item.get_metadata(0)
	if data is Dictionary:
		data["status"] = 1
		tree_item.set_metadata(0, data)

func _on_ftp_progress(file_name: String, current: int, total: int):
	var item = find_item_by_path(tree.get_root(), file_name)
	var percent = (float(current) / total) * 100.0 if total > 0 else 0.0
	if item:
		var old_percent = item.get_metadata(2)
		if old_percent == null or not is_equal_approx(old_percent, percent):
			item.set_metadata(2, percent)
	file_progress_bytes[file_name] = current
	var sum_downloaded = 0
	for val in file_progress_bytes.values():
		sum_downloaded += val
	var total_percent = (float(sum_downloaded) / download_size) * 100.0 if download_size > 0 else 0.0
	var speed_text = FtpClient.format_file_size(int(current_speed_bytes_per_sec)) + "/s"
	var eta_text = "--:--"
	var bytes_left = download_size - sum_downloaded
	if current_speed_bytes_per_sec > 1024:
		var seconds_left = float(bytes_left) / current_speed_bytes_per_sec
		eta_text = format_seconds(max(0, seconds_left))
	download_title_info.text = "Size: [color=yellow]%s[/color] / [color=green]%s[/color] Speed: [color=magenta]%s[/color] ETA: [color=orange]%s[/color]" % [
		FtpClient.format_file_size(sum_downloaded),
		FtpClient.format_file_size(download_size),
		speed_text,
		eta_text
	]
	download_title_progress.value = total_percent

func _on_ftp_finished(file_name: String, success: bool):
	var tree_item = find_item_by_path(tree.get_root(), file_name)
	var data = tree_item.get_metadata(0)
	if data is Dictionary:
		data["status"] = 10 if success else 2
		tree_item.set_metadata(0, data)
		tree_item.set_text(3, "Done" if success else "Error")
		if not success:
			download_errors += 1
	active_downloads -= 1
	process_queue()
	_check_all_finished()

func _check_all_finished():
	if active_downloads == 0:
		var still_waiting = false
		var root = tree.get_root()
		if root:
			var current_item = root.get_first_child()
			while current_item:
				var data = current_item.get_metadata(0)
				if data is Dictionary and data.get("status") == 0:
					still_waiting = true
					break
				current_item = current_item.get_next()
		if not still_waiting:
			toggle_proxy_settings()
			btn_start_download.text = "Start Download"
			btn_start_download.self_modulate = Color.WHITE
			btn_open_sfdl.disabled = false
			if dowloads_canceled == false:
				if download_errors == 0:
					add_log("All downloads done!", "gold")
					if settings_allsoundoff == false:
						play_sound.stream = load("res://sounds/event_alldownloadscomplete.mp3")
						play_sound.play()
				else:
					add_log("All downloads done! Errors: " + str(download_errors), "red")
				if settings_use_extractor:
					if not settings_extractor_path.strip_edges().is_empty():
						Extractor.start_recursive_search_task(
							local_download_destination.path_join(sfdl_description),
							settings_extractor_path,
							settings_remove_archives
						)	
				download_stop_timestamp = int(Time.get_unix_time_from_system())
				if download_seconds == 0:
					download_seconds = download_stop_timestamp - download_start_timestamp
				else:
					download_seconds += download_stop_timestamp - download_start_timestamp
				if download_seconds > 0:
					var path = local_download_destination.path_join(sfdl_description)
					var bps = int(download_size / download_seconds)
					var human_speed = FtpClient.format_file_size(bps) + "/s"
					var size = FtpClient.format_file_size(download_size)
					var time = format_seconds(download_seconds)
					var upper = sfdl_uploader
					create_speedreport(path, human_speed, size, time, upper)
					download_seconds = 0
					download_start_timestamp = 0
					download_stop_timestamp = 0
				download_size = 0
				download_total_bytes = 0
				download_errors = 0
				download_job_counter += 1
				_on_auto_timer_timeout() # auto downloads
		else:
			process_queue()

func _on_open_sfdl_pressed() -> void:
	var file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.add_filter("*.sfdl; SFDL Files")
	file_dialog.use_native_dialog = true
	file_dialog.file_selected.connect(_on_sfdl_file_selected)
	add_child(file_dialog)
	file_dialog.popup_centered_ratio(0.4)

func _on_files_dropped(files: PackedStringArray):
	for file_path in files:
		if file_path.get_extension().to_lower() == "sfdl":
			_on_sfdl_file_selected(file_path)

func _on_sfdl_file_selected(path: String) -> void:
	var SFDLScript = load("res://sfdl.gd")
	if SFDLScript:
		var parser_instanz = SFDLScript.new()
		sfdl_data.clear()
		sfdl_data = parser_instanz.parse_sfdl_xml(path, sfdl_password)
		if sfdl_data.is_empty():
			add_log("[SFDL]: Error reading: " + path)
		else:
			var _description = sfdl_data.get("Description")
			if _description.strip_edges().is_empty():
				_description = sfdl_data["Packages"][0]["Packagename"]
				if _description.strip_edges().is_empty():
					_description = path
			sfdl_description = _description
			add_log("[SFDL]: Loaded & decoded successfully: " + _description)
			if settings_allsoundoff == false:
				play_sound.stream = load("res://sounds/event_sfdl_loaded.mp3")
				play_sound.play()
			_on_refresh_pressed() # reset file tree
			max_concurrent_downloads = sfdl_data.get("MaxDownloadThreads").to_int()
			if max_concurrent_downloads < 1 or max_concurrent_downloads > 10:
				max_concurrent_downloads = 3
			sfdl_uploader = sfdl_data.get("Uploader")
			var _Username = sfdl_data["ConnectionInfo"].get("Username")
			if _Username == null or _Username.strip_edges().is_empty():
				sfdl_data["ConnectionInfo"]["Username"] = "anonymous"
			var _Password = sfdl_data["ConnectionInfo"].get("Password")
			if _Password == null or _Password.strip_edges().is_empty():
				sfdl_data["ConnectionInfo"]["Password"] = "graf@sauger.hart"	
			if settings_auto_download:
				rename_to_hidden(path)
			start_ftp_index(
				sfdl_data["ConnectionInfo"].get("Host"),
				sfdl_data["ConnectionInfo"].get("Port").to_int(),
				sfdl_data["ConnectionInfo"].get("Username"),
				sfdl_data["ConnectionInfo"].get("Password"),
				sfdl_data["Packages"][0]["BulkFolderList"][0],
				_description
			)

func process_queue():
	var root = tree.get_root()
	if not root or active_downloads >= max_concurrent_downloads:
		return
	var current_item = root.get_first_child()
	while current_item:
		var data = current_item.get_metadata(0)
		if data is Dictionary and data.get("status") == 0 and not data.get("is_dir", false):
			current_item.set_text(3, "Loading...")
			data["status"] = 1
			current_item.set_metadata(0, data)
			start_next_download(data.get("path"))
			btn_open_download_path.disabled = false
			if active_downloads >= max_concurrent_downloads:
				break
		current_item = current_item.get_next()
	toggle_proxy_settings()

func compare_paths(file_name):
	var tree_item = find_item_by_path(tree.get_root(), file_name)
	var data = tree_item.get_metadata(0)
	var remote_path = data["path"]
	var search_term = sfdl_description
	var relative_sub_path = ""
	var pos = remote_path.find(search_term)
	if pos != -1:
		relative_sub_path = remote_path.substr(pos + search_term.length())
	else:
		relative_sub_path = file_name.get_file()
	if relative_sub_path.begins_with("/"):
		relative_sub_path = relative_sub_path.substr(1)
	return relative_sub_path

func start_next_download(file_name):
	if dowloads_canceled == true:
		return
	var tree_item = find_item_by_path(tree.get_root(), file_name)
	var data = tree_item.get_metadata(0)
	if not data or not data.has("path"):
		return
	data["status"] = 1
	tree_item.set_metadata(0, data)
	active_downloads += 1
	add_log("Downloading now: %s" % file_name, "cyan")
	var remote_path = data["path"]
	var relative_sub_path = compare_paths(file_name)
	var dest_file = local_download_destination.path_join(sfdl_description).path_join(relative_sub_path)
	FtpClient.start_ftp_download(
		sfdl_data["ConnectionInfo"].get("Host"),
		sfdl_data["ConnectionInfo"].get("Port").to_int(),
		sfdl_data["ConnectionInfo"].get("Username"),
		sfdl_data["ConnectionInfo"].get("Password"),
		remote_path,
		dest_file
	)

func _on_download_completed(file_name):
	file_items[file_name].status = 10
	active_downloads -= 1
	add_log("Done: %s" % file_name, "green")
	process_queue()

func _on_download_failed(file_name):
	file_items[file_name].status = 2
	active_downloads -= 1
	add_log("Download error: %s" % file_name, "red")
	process_queue()

func _on_start_download_pressed() -> void:
	if active_downloads > 0:
		download_stop_timestamp = int(Time.get_unix_time_from_system())
		download_seconds += download_start_timestamp - download_stop_timestamp
		dowloads_canceled = true
		FtpClient.stop_all_downloads()
		active_downloads = 0
		toggle_proxy_settings()
		add_log("All downloads cancelled!", "red")
		if settings_allsoundoff == false:
			play_sound.stream = load("res://sounds/event_download-stop.mp3")
			play_sound.play()
		btn_start_download.text = "Start Download"
		btn_start_download.self_modulate = Color.WHITE
		btn_open_sfdl.disabled = false
		return
	download_start_timestamp = int(Time.get_unix_time_from_system())
	download_stop_timestamp = 0
	dowloads_canceled = false
	add_log("Downloading ...", "yellow")
	if settings_allsoundoff == false:
		play_sound.stream = load("res://sounds/event_download-start.mp3")
		play_sound.play()
	btn_start_download.text = "Stop Download"
	btn_start_download.self_modulate = Color(0.875, 0.072, 0.0, 1.0)
	btn_open_sfdl.disabled = true
	if typeof(file_items) != TYPE_DICTIONARY:
		push_error("Error: file_items is not a dictionary!")
		return
	for tree_item in file_items.values():
		if not tree_item is TreeItem:
			continue
		var data = tree_item.get_metadata(0)
		if data is Array and data.size() > 0:
			data = data[0]
		if data is Dictionary:
			if not data.get("is_dir", false):
				data["status"] = 0
				tree_item.set_metadata(0, data)
				tree_item.set_text(3, "Waiting...")
	active_downloads = 0
	download_errors = 0
	process_queue()

func find_item_by_path(parent: TreeItem, target_path: String) -> TreeItem:
	if not parent:
		return null
	var current_item = parent.get_first_child()
	while current_item:
		var meta = current_item.get_metadata(0)
		if meta is Dictionary and meta.get("path") == target_path:
			return current_item
		current_item = current_item.get_next()
	return null

func _on_open_download_path_pressed() -> void:
	if not sfdl_description.is_empty() and not local_download_destination.is_empty():
		var dest_path = local_download_destination.path_join(sfdl_description)
		if DirAccess.dir_exists_absolute(dest_path):
			OS.shell_open(dest_path)
		else:
			add_log("[Path] Download path not yet created!", "red")
		
func _on_quit_dialog_canceled():
	add_log("Continue ...", "blue")

func _on_path_dialog_pressed() -> void:
	path_dialog = FileDialog.new()
	add_child(path_dialog)
	path_edit.editable = false
	path_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	path_dialog.access = FileDialog.ACCESS_FILESYSTEM
	path_dialog.title = "Select download location"
	path_dialog.use_native_dialog = true
	path_dialog.dir_selected.connect(_on_dir_selected)
	path_dialog.current_dir = path_edit.text
	path_dialog.popup_centered_ratio(0.4)

func _on_dir_selected(dir: String):
	path_edit.text = dir
	local_download_destination = dir
	add_log("New download destination: " + dir, "green")
	var config = ConfigFile.new()
	config.set_value("Settings", "download_path", dir)
	config.save(SAVE_PATH)
	path_edit.text = dir

func _on_music_pressed() -> void:
	if music_player.playing:
		# music_player.stop()
		stop_dance()
		var bus_index = AudioServer.get_bus_index("Music")
		AudioServer.set_bus_mute(bus_index, true)
		music_player.stream_paused = true
		btn_music.icon = ICON_OFF
		if settings_allsoundoff == false:
			play_sound.stream = load("res://sounds/event_music_off.mp3")
			play_sound.play()
		timer.stop()
		add_log("🎵 Off! ", "pink")
	else:
		if music_player.stream:
			# music_player.play()
			start_dance()
			var bus_index = AudioServer.get_bus_index("Music")
			AudioServer.set_bus_mute(bus_index, false)
			music_player.stream_paused = false
			if settings_allsoundoff == false:
				play_sound.stream = load("res://sounds/event_music_on.mp3")
				play_sound.play()
			start_random_timer()
		else:
			_play_random_song()
		btn_music.icon = ICON_ON
		add_log("🎵 On! ", "pink")

func create_speedreport(file_path: String, speed: String, size: String, time: String, upper: String):
	var content = (
		"[size=3][b]GodotSauger Speedreport[/b][/size]\n"
		+ "[hr][/hr]\n"
		+ "Download: %s\n"
		+ "Size: %s\n"
		+ "Speed: %s\n"
		+ "Time: %s\n"
		+ "Thanks %s (Upper)!\n"
		+ "[hr][/hr]\n"
		+ "[i][size=1]GodotSauger[/size][/i]\n"
	) % [sfdl_description, size, speed, time, upper]
	var speedreport_txt = file_path.path_join("speedreport.txt")
	var file = FileAccess.open(speedreport_txt, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		add_log("[Info] Speedreport created: " + speedreport_txt, "magenta")
	else:
		add_log("[Info] Speedreport error: %s" % error_string(FileAccess.get_open_error()), "red")

func _on_settings_pressed() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(main_ui, "position:y", main_ui.position.y + 700, 0.8)
	tween.tween_property(main_ui, "modulate:a", 0.0, 0.6)
	tween.set_parallel(false)
	tween.tween_callback(func():
		main_ui.hide()
		settings_ui.show()
	)
	
func _on_settings_back_pressed() -> void:
	save_all_proxy_fields()
	settings_ui.hide()
	main_ui.show()
	main_ui.position.y = main_ui_original_pos.y + 700
	main_ui.modulate.a = 0.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(main_ui, "position:y", main_ui_original_pos.y, 1.2)
	tween.tween_property(main_ui, "modulate:a", 1.0, 1.0)

func _on_x_rel_pressed() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(main_ui, "position:y", main_ui.position.y + 700, 0.8)
	tween.tween_property(main_ui, "modulate:a", 0.0, 0.6)
	tween.set_parallel(false)
	tween.tween_callback(func():
		main_ui.hide()
		xrel_ui.show()
	)

func _on_x_rel_back_pressed() -> void:
	xrel_ui.hide()
	main_ui.show()
	main_ui.position.y = main_ui_original_pos.y + 700
	main_ui.modulate.a = 0.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(main_ui, "position:y", main_ui_original_pos.y, 1.2)
	tween.tween_property(main_ui, "modulate:a", 1.0, 1.0)

func _on_check_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		settings_fullscreen = true
		save_settings("settings_fullscreen", true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		settings_fullscreen = false
		save_settings("settings_fullscreen", false)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_all_sound_off_toggled(toggled_on: bool) -> void:
	if toggled_on:
		settings_allsoundoff = true
		save_settings("settings_allsoundoff", true)
		music_player.stop()
		btn_music.disabled = true
		btn_music.icon = ICON_OFF
		timer.stop()
		stop_dance()
	else:
		settings_allsoundoff = false
		save_settings("settings_allsoundoff", false)
		btn_music.disabled = false
		btn_music.icon = ICON_ON
		start_random_timer()
		_play_random_song()
		play_sound.stream = load("res://sounds/event_music_on.mp3")
		play_sound.play()
		start_dance()

func _on_open_rar_pressed() -> void:
	OS.shell_open("https://www.rarlab.com/rar_add.htm")

func _on_open_7_zip_pressed() -> void:
	OS.shell_open("https://www.7-zip.org/download.html")

func _on_remove_archives_toggled(toggled_on: bool) -> void:
	if toggled_on:
		settings_remove_archives = true
	else:
		settings_remove_archives = false
	save_settings("extractor_remote_archives", toggled_on)

func _on_extractor_location_open_pressed() -> void:
	var file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.use_native_dialog = true
	file_dialog.filters = ["* ; Executables / Binaries"]
	file_dialog.file_selected.connect(_on_extractor_tool_selected)
	add_child(file_dialog)
	file_dialog.popup_centered_ratio(0.4)
	
func _on_extractor_tool_selected(path: String) -> void:
	if not FileAccess.file_exists(path):
		add_log("[Extractor] Not a valid tool: " + path, "red")
		return
	settings_extractor_path = path
	$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer2/ExtractorLocation.text = path
	save_settings("extractor_path", settings_extractor_path)

func _on_extractor_use_toggled(toggled_on: bool) -> void:
	if toggled_on:
		settings_use_extractor = true
	else:
		settings_use_extractor = false
	save_settings("extractor_use", toggled_on)

func setup_msaa_button():
	var btn = $ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer/MSAAButton
	btn.add_item("MSAA Off", 0)
	btn.add_item("MSAA 2x", 1)
	btn.add_item("MSAA 4x", 2)
	btn.add_item("MSAA 8x", 3)
	btn.item_selected.connect(_on_msaa_selected)

func _on_msaa_selected(index: int):
	get_viewport().msaa_3d = index as Viewport.MSAA
	save_settings("msaa_level", index)

func _on_fxaa_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA as Viewport.ScreenSpaceAA
	else:
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED as Viewport.ScreenSpaceAA
	save_settings("fxaa_enabled", toggled_on)

func _on_taa_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/FXAAButton.button_pressed = false
		_on_fxaa_button_toggled(false)
	get_viewport().use_taa = toggled_on
	if toggled_on:
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		get_viewport().fsr_sharpness = 0.5
	save_settings("taa_enabled", toggled_on)

func check_render_compatibility():
	var current_renderer = ProjectSettings.get_setting("rendering/renderer/rendering_method")
	if current_renderer == "gl_compatibility":
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/TAAButton.disabled = true
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/TAAButton.tooltip_text = "TAA disabled in compatibility mode (OpenGL)."
		get_viewport().use_taa = false
	else:
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/TAAButton.disabled = false

func save_settings(settings_key: String, data: Variant):
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		add_log("[SAVE] Error loading config file: " + err, "red")
		return
	config.set_value("Settings", settings_key, data)
	var save_err = config.save(SAVE_PATH)
	if save_err != OK:
		add_log("[SAVE] Error saving file: " + save_err, "red")
		
func load_window_settings():
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		var w = config.get_value("Settings", "window_width", 1280)
		var h = config.get_value("Settings", "window_height", 720)
		DisplayServer.window_set_size(Vector2i(w, h))
		var px = config.get_value("Settings", "window_pos_x", 100)
		var py = config.get_value("Settings", "window_pos_y", 100)
		DisplayServer.window_set_position(Vector2i(px, py))

func _on_extractor_finished(success, output):
	if success:
		add_log("[Extractor] (OK) Done!", "green")
	else:
		var output_text = "\n".join(output)
		add_log("[Extractor] Error: " + output_text, "red")

func _on_use_proxy_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		settings_proxy_use = true
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/UseProxyButton.button_pressed = true
	else:
		settings_proxy_use = false
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/UseProxyButton.button_pressed = false
	save_settings("proxy_use", toggled_on)
	
func save_all_proxy_fields():
	var www_port = int($ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/HBoxContainer/WebserverPort.value)
	settings_webserver_port = www_port
	save_settings("webserver_port", settings_webserver_port)
	var p_host = $ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer3/ProxyHost.text
	var p_port = int($ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer4/ProxyPort.value)
	var p_user = $ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer5/ProxyUser.text
	var p_pass = $ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer6/ProxyPass.text
	settings_proxy_host = p_host.strip_edges()
	save_settings("proxy_host", settings_proxy_host)
	if p_port > 1 and p_port <= 65535:
		settings_proxy_port = p_port
		save_settings("proxy_port", settings_proxy_port)
	settings_proxy_user = p_user.strip_edges()
	save_settings("proxy_user", settings_proxy_user)
	settings_proxy_pass = p_pass.strip_edges()
	save_settings("proxy_pass", settings_proxy_pass)
	var proxy_data = {
			"use": settings_proxy_use,
			"host": settings_proxy_host,
			"port": settings_proxy_port,
			"user": settings_proxy_user,
			"pass": settings_proxy_pass
		}
	FtpClient.set_proxy_data(proxy_data)

# disable proxy settings / control while ftp is running
func toggle_proxy_settings():
	if active_downloads > 0:
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/UseProxyButton.disabled = true
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer3/ProxyHost.editable = false
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer4/ProxyPort.editable = false
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer4/ProxyPort.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer5/ProxyUser.editable = false
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer6/ProxyPass.editable = false
	else:
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/UseProxyButton.disabled = false
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer3/ProxyHost.editable = true
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer4/ProxyPort.editable = true
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer4/ProxyPort.mouse_filter = Control.MOUSE_FILTER_STOP
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer5/ProxyUser.editable = true
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer6/ProxyPass.editable = true

func _on_x_rel_search_text_submitted(new_text: String) -> void:
	if not new_text.strip_edges().is_empty():
		start_web_search(new_text)
		$ControlWeb/VBoxContainer/HBoxContainer/xRELSearch.call_deferred("grab_focus")
		$ControlWeb/VBoxContainer/HBoxContainer/xRELSearch.call_deferred("select_all")

func _on_x_rel_search_button_pressed() -> void:
	var search_text = $ControlWeb/VBoxContainer/HBoxContainer/xRELSearch.text
	if not search_text.strip_edges().is_empty():
		start_web_search(search_text)
		$ControlWeb/VBoxContainer/HBoxContainer/xRELSearch.call_deferred("grab_focus")
		$ControlWeb/VBoxContainer/HBoxContainer/xRELSearch.call_deferred("select_all")

func start_web_search(search_text: String):
	if not search_text.strip_edges().is_empty():
		xrel_error.visible = false
		xrel_error.text = ""
		var api_script = load("res://web_api.gd")
		var api_manager = api_script.new()
		api_manager.name = "TempAPIManager"
		add_child(api_manager)
		api_manager.data_received.connect(_on_web_data_loaded, CONNECT_ONE_SHOT)
		api_manager.request_failed.connect(_on_web_error, CONNECT_ONE_SHOT)
		api_manager.data_received.connect(func(_data): api_manager.queue_free())
		api_manager.request_failed.connect(func(_msg): api_manager.queue_free())
		var url_safe_query = search_text.uri_encode().replace("%20", "+")
		api_manager.fetch_data("https://api.xrel.to/v2/search/releases.json?q=" + url_safe_query + "&scene=1&p2p=1")

func _on_web_data_loaded(data):
	xrel_tree.clear()
	var root = xrel_tree.create_item()
	xrel_tree.columns = 1
	xrel_tree.set_hide_root(true)
	xrel_tree.hide_root = true
	
	var tota_results = data.get("total", 0)
	xrel_error.visible = true
	xrel_error.text = "[center][color=green]xREL Results: %d[/color][/center]" % tota_results
	
	if data.has("results") and data["results"] is Array:
		for item in data["results"]:
			var tree_item = xrel_tree.create_item(root)
			tree_item.set_text(0, item.get("dirname", "Unbekannt"))
			tree_item.set_custom_color(0, Color.WHITE)
			tree_item.set_metadata(0, item.get("link_href", ""))

	if data.has("p2p_results") and data["p2p_results"] is Array:
		for p2p_item in data["p2p_results"]:
			var p2p_item_node = xrel_tree.create_item(root)
			p2p_item_node.set_text(0, p2p_item.get("dirname", "Unbekannt"))
			p2p_item_node.set_custom_color(0, Color.YELLOW)
			p2p_item_node.set_custom_bg_color(0, Color(0.2, 0.2, 0, 0.3))
			p2p_item_node.set_metadata(0, p2p_item.get("link_href", ""))

func _on_web_error(msg):
	xrel_error.visible = true
	xrel_error.text = "[center][color=red]xREL Error: " + msg + "[/color][/center]"

func _on_auto_download_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		settings_auto_download = true
		if not auto_sfdl_timer.is_stopped():
			auto_sfdl_timer.stop()
		auto_sfdl_timer.start(settings_auto_refresh_time)
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/AutoDownloadButton.button_pressed = true
	else:
		settings_auto_download = false
		auto_sfdl_timer.stop()
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/AutoDownloadButton.button_pressed = false
	save_settings("auto_download", toggled_on)

func _on_auto_timer_value_changed(value: float) -> void:
	settings_auto_refresh_time = value
	if settings_auto_download:
		if not auto_sfdl_timer.is_stopped():
			auto_sfdl_timer.stop()
		auto_sfdl_timer.start(settings_auto_refresh_time)
	save_settings("auto_refresh_time", settings_auto_refresh_time)

func _on_auto_timer_timeout():
	if active_downloads == 0:
		if settings_auto_download:
			if DirAccess.dir_exists_absolute(settings_auto_sfdl_path):
				get_sfdl_file_from_path(settings_auto_sfdl_path)
				if not auto_sfdl_timer.is_stopped():
					auto_sfdl_timer.stop()
				auto_sfdl_timer.start(settings_auto_refresh_time)
	else:
		if not auto_sfdl_timer.is_stopped():
			auto_sfdl_timer.stop()
		auto_sfdl_timer.start(settings_auto_refresh_time)

func _on_auto_download_path_button_pressed() -> void:
	var auto_download_dialog = FileDialog.new()
	add_child(auto_download_dialog)
	auto_download_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	auto_download_dialog.access = FileDialog.ACCESS_FILESYSTEM
	auto_download_dialog.title = "Select SFDL location"
	auto_download_dialog.use_native_dialog = true
	auto_download_dialog.dir_selected.connect(_on_auto_download_path_selected)
	auto_download_dialog.current_dir = path_edit.text
	auto_download_dialog.popup_centered_ratio(0.4)

func _on_auto_download_path_selected(dir: String):
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	settings_auto_sfdl_path = dir
	$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/HBoxContainer7/AutoDownloadPath.text = settings_auto_sfdl_path
	save_settings("auto_sfdl_path", settings_auto_sfdl_path)

func get_sfdl_file_from_path(folder_path: String):
	var dir = DirAccess.open(folder_path)
	if not dir:
		return
	var oldest_file = ""
	var oldest_time = 9223372036854775807
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".sfdl") and not file_name.begins_with("."):
			var full_path = folder_path.path_join(file_name)
			var mod_time = FileAccess.get_modified_time(full_path)
			if mod_time < oldest_time:
				oldest_time = mod_time
				oldest_file = full_path
		file_name = dir.get_next()
	if not oldest_file == "":
		add_log("[AUTO] Next: " + oldest_file.get_file(), "orange")
		_on_sfdl_file_selected(oldest_file)
	else:
		if download_job_counter > 0:
			if settings_auto_shutdown_pc:
				start_shutdown_sequence() # shutdown pc

func rename_to_hidden(file_path: String) -> Error:
	if file_path == "" or not FileAccess.file_exists(file_path):
		return ERR_FILE_NOT_FOUND
	var dir_path = file_path.get_base_dir()
	var file_name = file_path.get_file()
	var new_path = dir_path.path_join("." + file_name)
	var dir = DirAccess.open(dir_path)
	return dir.rename(file_path, new_path)

func _on_x_rel_tree_item_activated() -> void:
	var selected_item = xrel_tree.get_selected()
	if not selected_item:
		return
	var url = selected_item.get_metadata(0)
	if url and url.begins_with("http"):
		OS.shell_open(url)

func _on_auto_shutdown_pc_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		var platform = OS.get_name()
		var success = false
		match platform:
			"macOS":
				success = check_mac_permissions()
			"Linux", "FreeBSD":
				success = check_linux_permissions()
			"Windows":
				success = true
		if success:
			add_log("[AUTO] (Shutdown PC) PC will shutdown after the last download!", "green")
			$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/AutoShutdownPCButton.button_pressed = true
			save_settings("auto_shutdown_pc", true)
		else:
			add_log("[AUTO] (Shutdown PC) No system permission!", "red")
			$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/AutoShutdownPCButton.button_pressed = false
			save_settings("auto_shutdown_pc", false)
	else:
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/AutoShutdownPCButton.button_pressed = false
		save_settings("auto_shutdown_pc", false)

func check_mac_permissions() -> bool:
	var output = []
	var exit_code = OS.execute("osascript", ["-e", "tell application \"System Events\" to get name"], output, true)
	return exit_code == 0

func check_linux_permissions() -> bool:
	var output = []
	var exit_code = OS.execute("bash", ["-c", "command -v systemctl && systemctl can-poweroff"], output, true)
	if exit_code == 0 and output.size() > 0 and output[0].strip_edges() == "yes":
		return true
	return false

func shutdown_pc():
	var os_name = OS.get_name()
	var command = ""
	var args = []
	match os_name:
		"Windows":
			command = "shutdown"
			args = ["/s", "/t", "0"]
		"macOS":
			command = "osascript"
			args = ["-e", "tell application \"System Events\" to shut down"]
		"Linux", "FreeBSD":
			command = "shutdown"
			args = ["now"]
	if command != "":
		OS.execute(command, args, [], false)
		
func start_shutdown_sequence():
	remaining_seconds = 30
	update_dialog_text()
	DisplayServer.window_request_attention()
	DisplayServer.window_move_to_foreground()
	shutdown_dialog.popup_centered()
	run_countdown()

func run_countdown():
	while remaining_seconds > 0 and shutdown_dialog.visible:
		update_dialog_text()
		await get_tree().create_timer(1.0).timeout
		if not shutdown_dialog.visible:
			return
		remaining_seconds -= 1
		if remaining_seconds <= 0:
			_on_shutdown_confirmed()

func update_dialog_text():
	shutdown_dialog.dialog_text = "System will shutdown in\n\n" + str(remaining_seconds) + "\n\nseconds!"

func _on_shutdown_confirmed():
	shutdown_dialog.hide()
	add_log("[AUTO] (Shutdown PC): Your system will shotdown now!", "blue")
	shutdown_pc()

func _on_shutdown_cancelled():
	shutdown_dialog.hide()
	add_log("[AUTO] (Shutdown PC): User abort! System will -NOT- shutdown.", "green")
	remaining_seconds = -1
	settings_auto_shutdown_pc = false
	$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer/AutoShutdownPCButton.button_pressed = false
	save_settings("auto_shutdown_pc", false)

func webserver_start():
	web_server = HttpServer.new()
	web_server.log_requested.connect(add_log)
	web_server.port = settings_webserver_port
	if local_download_destination.is_empty():
		local_download_destination = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		if local_download_destination == "":
			local_download_destination = OS.get_user_data_dir()
	web_server.upload_dir = local_download_destination
	add_child(web_server)
	
func webserver_stop():
	if web_server:
		web_server.stop_server()
		web_server.queue_free()
		
func _on_webserver_button_toggled(toggled_on: bool) -> void:
	var www_port = int($ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/HBoxContainer/WebserverPort.value)
	settings_webserver_port = www_port
	if toggled_on:
		settings_webserver_run = true
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/WebserverButton.button_pressed = true
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/HBoxContainer/WebserverPort.editable = false
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/HBoxContainer/WebserverPort.mouse_filter = Control.MOUSE_FILTER_IGNORE
		webserver_start()
	else:
		settings_webserver_run = true
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/HBoxContainer/WebserverPort.editable = true
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/HBoxContainer/WebserverPort.mouse_filter = Control.MOUSE_FILTER_STOP
		$ControlSettings/ScrollContainer/VBoxContainer/VBoxContainer2/WebserverButton.button_pressed = false
		webserver_stop()
	save_settings("webserver_run", toggled_on)
	save_settings("webserver_port", www_port)

func start_dance():
	for child in $hero_dance.find_children("*", "MeshInstance3D"):
		child.transparency = 0.0
	$hero_dance.visible = true
	anim_player.play("Armature|All_Night_Dance|baselayer")

func stop_dance():
	var tween = create_tween()
	for child in $hero_dance.find_children("*", "MeshInstance3D"):
		tween.parallel().tween_property(child, "transparency", 1.0, 0.5)
	await tween.finished
	$hero_dance.visible = false
	anim_player.stop()
	'''
	if skeleton:
		for i in skeleton.get_bone_count():
			var rest_tr = skeleton.get_bone_rest(i)
			skeleton.set_bone_pose_position(i, rest_tr.origin)
			skeleton.set_bone_pose_rotation(i, rest_tr.basis.get_rotation_quaternion())
			skeleton.set_bone_pose_scale(i, rest_tr.basis.get_scale())
	'''

func _cleanup_and_quit():
	FtpClient.abort_all = true
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()
