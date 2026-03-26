extends Camera3D

@export var max_tilt_angle: float = 5.0
@export var lerp_speed: float = 5.0

var base_rotation: Vector3

func _ready():
	base_rotation = rotation_degrees

func _process(delta):
	var mouse_pos = get_viewport().get_mouse_position()
	var window_size = get_viewport().get_visible_rect().size
	mouse_pos.x = clamp(mouse_pos.x, 0, window_size.x)
	mouse_pos.y = clamp(mouse_pos.y, 0, window_size.y)
	var x_ratio = (mouse_pos.x / window_size.x) * 2.0 - 1.0
	var y_ratio = (mouse_pos.y / window_size.y) * 2.0 - 1.0
	var target_tilt_x = -y_ratio * max_tilt_angle + base_rotation.x
	var target_tilt_y = -x_ratio * max_tilt_angle + base_rotation.y
	rotation_degrees.x = lerp(rotation_degrees.x, target_tilt_x, lerp_speed * delta)
	rotation_degrees.y = lerp(rotation_degrees.y, target_tilt_y, lerp_speed * delta)
