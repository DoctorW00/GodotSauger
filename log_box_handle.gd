extends Panel

@onready var log_box = $"../LogBox"
var dragging = false

func _ready():
	mouse_default_cursor_shape = Control.CURSOR_VSIZE

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
	if event is InputEventMouseMotion and dragging:
		var new_height = log_box.custom_minimum_size.y + event.relative.y
		var max_h = get_viewport_rect().size.y - 30
		log_box.custom_minimum_size.y = clamp(new_height, 30, max_h)
