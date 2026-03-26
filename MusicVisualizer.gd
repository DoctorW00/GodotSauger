extends Node2D

@export var bar_count: int = 32
@export var bar_width: float = 25.0
@export var bar_max_height: float = 350.0
@export var spacing: float = 10.0
@export var glow_intensity: float = 0.5
@export var color_low: Color = Color.RED
@export var color_high: Color = Color.WHITE

var spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance
var bars: Array[TextureRect] = [] 
const FREQ_MAX = 11025.0
const MIN_DB = 65

var music_player: AudioStreamPlayer

func _ready():
	var bus_idx = AudioServer.get_bus_index("Music")
	if bus_idx == -1:
		bus_idx = 0
	var effect = AudioServer.get_bus_effect_instance(bus_idx, 0)
	if effect is AudioEffectSpectrumAnalyzerInstance:
		spectrum_analyzer = effect
	create_bars()

func create_bars():
	var total_width = (bar_count * bar_width) + ((bar_count - 1) * spacing)
	var start_x = (get_viewport_rect().size.x - total_width) / 2
	var bottom_y = get_viewport_rect().size.y
	for i in range(bar_count):
		var bar = TextureRect.new()
		var grad = Gradient.new()
		grad.add_point(0.0, color_low)
		grad.add_point(1.0, color_high)
		var tex = GradientTexture2D.new()
		tex.gradient = grad
		tex.fill_from = Vector2(0, 1)
		tex.fill_to = Vector2(0, 0)
		bar.texture = tex
		bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bar.size = Vector2(bar_width, bar_max_height)
		bar.position.x = start_x + (i * (bar_width + spacing))
		bar.position.y = bottom_y - bar_max_height 
		bar.pivot_offset = Vector2(bar_width / 2, bar_max_height)
		bar.scale.y = 0
		add_child(bar)
		bars.append(bar)

func _process(_delta):
	if not spectrum_analyzer:
		return
	music_player = get_node_or_null("../MusicPlayer")
	if not music_player:
		music_player = get_tree().current_scene.get_node_or_null("MusicPlayer")
		if not music_player:
			return
	var is_active = music_player.playing and not music_player.stream_paused
	var prev_hz = 0
	for i in range(bar_count):
		var target_energy = 0.0
		if is_active:
			var hz = (i + 1) * FREQ_MAX / bar_count
			var magnitude = spectrum_analyzer.get_magnitude_for_frequency_range(prev_hz, hz).length()
			target_energy = clamp((linear_to_db(magnitude) + MIN_DB) / MIN_DB, 0.0, 1.0)
			prev_hz = hz
		bars[i].scale.y = lerp(bars[i].scale.y, target_energy, 0.2)
		bars[i].modulate = Color(0.435, 0.161, 0.0, 1.0) * (1.0 + target_energy * glow_intensity)
