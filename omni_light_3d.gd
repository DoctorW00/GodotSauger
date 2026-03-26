extends OmniLight3D

@export var depth: float = 2.0

func _process(_delta):
	var viewport = get_viewport()
	var mouse_pos = viewport.get_mouse_position()
	var camera = viewport.get_camera_3d()
	if camera:
		global_position = camera.project_position(mouse_pos, depth)
