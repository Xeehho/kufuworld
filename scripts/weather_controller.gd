extends Node

@export var time_scale: float = 60.0
@export var start_hour: float = 8.0

enum Weather {CLEAR, CLOUDY, RAIN, SNOW, FOG}

var world_time: float = 0.0
var current_hour: float = start_hour
var current_weather: Weather = Weather.CLEAR
var weather_target: Weather = Weather.CLEAR
var weather_transition: float = 0.0
var weather_duration: float = 0.0

var day_colors: Dictionary = {}
var night_color: Color = Color(0.25, 0.28, 0.65, 1.0)
var dawn_color: Color = Color(0.75, 0.55, 0.6, 1.0)
var noon_color: Color = Color(1.0, 0.95, 0.88, 1.0)
var dusk_color: Color = Color(0.7, 0.45, 0.55, 1.0)

var rain_particles: GPUParticles2D = null
var snow_particles: GPUParticles2D = null
var fog_overlay: ColorRect = null

@onready var canvas_modulate: CanvasModulate = $"../CanvasModulate"

func _ready():
	world_time = start_hour * 60.0 * time_scale
	_create_weather_particles()
	_setup_day_colors()
	pick_new_weather()
	print("[Weather] Controller ready - start hour " + str(start_hour))

func _setup_day_colors():
	day_colors = {
		6: dawn_color,
		12: noon_color,
		18: dusk_color,
		22: night_color
	}

func _create_weather_particles():
	rain_particles = GPUParticles2D.new()
	rain_particles.name = "RainParticles"
	rain_particles.emitting = false
	rain_particles.amount = 120
	rain_particles.lifetime = 1.2
	rain_particles.process_material = _make_rain_material()
	rain_particles.z_index = 1000
	rain_particles.one_shot = false
	add_child(rain_particles)

	snow_particles = GPUParticles2D.new()
	snow_particles.name = "SnowParticles"
	snow_particles.emitting = false
	snow_particles.amount = 80
	snow_particles.lifetime = 3.0
	snow_particles.process_material = _make_snow_material()
	snow_particles.z_index = 1000
	snow_particles.one_shot = false
	add_child(snow_particles)

func _make_rain_material() -> ParticleProcessMaterial:
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 15.0
	mat.gravity = Vector3(0, 800, 0)
	mat.initial_velocity_min = 400.0
	mat.initial_velocity_max = 700.0
	mat.scale_min = 1.0
	mat.scale_max = 3.0
	mat.color = Color(0.4, 0.5, 0.7, 0.6)
	return mat

func _make_snow_material() -> ParticleProcessMaterial:
	var mat = ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 30.0
	mat.gravity = Vector3(0, 20, 0)
	mat.initial_velocity_min = 30.0
	mat.initial_velocity_max = 80.0
	mat.scale_min = 2.0
	mat.scale_max = 5.0
	mat.color = Color(1, 1, 1, 0.7)
	return mat

func _process(delta):
	world_time += delta * time_scale
	current_hour = fmod(world_time / (60.0 * time_scale), 24.0)
	_update_lighting(delta)
	_update_weather(delta)
	_update_particles()

func _update_lighting(_delta):
	if not canvas_modulate:
		return
	var c = _get_hour_color(current_hour)
	canvas_modulate.color = c
	GameManager.world_hour = current_hour
	GameManager.is_daytime = is_daytime()

func _get_hour_color(hour: float) -> Color:
	if hour < 5:
		return night_color
	elif hour < 6.5:
		return night_color.lerp(dawn_color, (hour - 5) / 1.5)
	elif hour < 10:
		return dawn_color.lerp(noon_color, (hour - 6.5) / 3.5)
	elif hour < 15:
		return noon_color
	elif hour < 18:
		return noon_color.lerp(dusk_color, (hour - 15) / 3.0)
	elif hour < 20:
		return dusk_color.lerp(night_color, (hour - 18) / 2.0)
	return night_color

func _update_weather(delta):
	weather_duration -= delta
	if weather_duration <= 0:
		pick_new_weather()
	weather_transition = min(weather_transition + delta * 0.5, 1.0)
	GameManager.is_raining = current_weather == Weather.RAIN
	GameManager.is_snowing = current_weather == Weather.SNOW

func _update_particles():
	if rain_particles:
		rain_particles.emitting = current_weather == Weather.RAIN
	if snow_particles:
		snow_particles.emitting = current_weather == Weather.SNOW

func pick_new_weather():
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var r = rng.randf()
	var h = current_hour
	if h > 20 or h < 6:
		current_weather = Weather.CLEAR if r < 0.6 else Weather.FOG
	elif h < 10:
		current_weather = Weather.FOG if r < 0.3 else (Weather.CLEAR if r < 0.85 else Weather.RAIN)
	else:
		if r < 0.45:
			current_weather = Weather.CLEAR
		elif r < 0.7:
			current_weather = Weather.CLOUDY
		elif r < 0.9:
			current_weather = Weather.RAIN
		else:
			current_weather = Weather.FOG
	weather_duration = rng.randf_range(30.0, 180.0)
	weather_transition = 0.0
	print("[Weather] Now: " + _weather_name(current_weather) + " for " + str(int(weather_duration)) + "s")

func _weather_name(w: Weather) -> String:
	match w:
		Weather.CLEAR: return "晴天"
		Weather.CLOUDY: return "多云"
		Weather.RAIN: return "下雨"
		Weather.SNOW: return "下雪"
		Weather.FOG: return "大雾"
	return ""

func get_world_hour() -> float:
	return current_hour

func is_daytime() -> bool:
	return current_hour >= 6 and current_hour < 20

func is_night() -> bool:
	return not is_daytime()

func get_current_weather() -> Weather:
	return current_weather
