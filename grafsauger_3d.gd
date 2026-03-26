extends Node3D

@onready var light_l = get_node("../EyeLeft")
@onready var light_r = get_node("../EyeRight")

@export var base_energy: float = 1.0
@export var min_energy: float = 0.1
@export var blink_speed: float = 2.0

func _process(_delta):
	var raw_pulse = (sin(Time.get_ticks_msec() * 0.001 * blink_speed) + 1.0) / 2.0
	var current_energy = lerp(min_energy, base_energy, raw_pulse)
	light_l.light_energy = current_energy
	light_r.light_energy = current_energy
