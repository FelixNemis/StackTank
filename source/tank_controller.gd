extends RigidBody3D

@export var player_controlled: = false

@export var speed: = 0.5
@export var drive_turn: = 1.4
@export var stationary_turn: = 1.4

@export var acceleration_factor: = 6.0

@export var fodder: = false

@onready var model = $TankModel

@export var alive: = true

@export var aim_factor: = 6.0

var bs = preload("res://scenes/objects/shot.tscn")

const CONST_ACCEL_MUL: = 1
const CONST_ROTATION_MUL: = 200
const SPEED_MULT: = 10
const FRICTION_CONTEXT_LERP: = 1.0
const BRAKE_LERP: = 20.0
const MIN_BRAKE_EFFECT: = 500.0
const MAX_TURN_VELOCITY: = PI
const MAX_MOVING_TURN_VELOCITY: = MAX_TURN_VELOCITY/2

var tread_linear_velocty_l: = 0.0
var tread_linear_velocty_r: = 0.0

var grounded: = true

const DUSTY_TIME: = 0.6
var dusty_timer = 0
var dusty_toggle: = false

var look_at_me: Node3D = null

var my_camera: Camera3D = null

func _ready():
	if fodder:
		pass
	
	if player_controlled:
		call_deferred("grab_camera")
		call_deferred("find_lookat")

func grab_camera():
	var root = get_tree().root.get_child(0)
	var cam = root.find_child("CameraCenter")
	if not cam:
		print("didnt find cam on " + root.name)
	else:
		my_camera = cam.find_child("Camera3D")
		$CameraDragger.remote_path = $CameraDragger.get_path_to(cam)

func find_lookat():
	var root = get_tree().root.get_child(0)
	look_at_me = root.find_child("Tank2")
	if not is_instance_valid(look_at_me):
		look_at_me = null

func find_auto_target():
	print("Target!")
	if not my_camera:
		return
	var tanks = get_all_alive_tanks()
	var camera_transform = my_camera.global_transform
	var view_vec: Vector3 = -camera_transform.basis.z
	
	var fov = deg_to_rad(my_camera.fov)
	var dist_to_me = (global_position - my_camera.global_position).length()
	
	var max_score: = -1.0
	var best_tank: Node3D = null
	for t in tanks:
		var pos_diff: Vector3 = t.global_position - camera_transform.origin
		if view_vec.dot(pos_diff.normalized()) < 0:
			print("bad dot")
			continue
		var ang = view_vec.angle_to(pos_diff)
		if ang > fov/2.0:
			print("out of fov")
			continue
		
		if not my_camera.is_tank_visible(t):
			print("ray fail")
			continue
		
		var flattened = (camera_transform.inverse() * t.global_position) * Vector3(1, 0, 1)
		var h_ang = Vector3.FORWARD.angle_to(flattened)
		var score = (2 - h_ang) * 2000.0
		
		score += max(0, 300 - (global_position - t.global_position).length())
		
		score += 100000 if pos_diff.length() >= dist_to_me else 0
		
		if score > max_score:
			best_tank = t
			max_score = score
	
	if best_tank:
		print("gottem")
		look_at_me = best_tank
	else:
		print("no tank")
		look_at_me = null
		
func hit():
	pass#die

func get_all_alive_tanks() -> Array:
	var alives = []
	for t in get_tree().get_nodes_in_group("TANK"):
		if t == self:
			continue
		if t.alive:
			alives.append(t)
	return alives

func dusty_off() -> void:
	dusty_toggle = false
	if dusty_timer > 0:
		return
	$Dusty.emitting = false

func dusty_on() -> void:
	dusty_toggle = true
	$Dusty.emitting = true
	dusty_timer = DUSTY_TIME

func dusty_process(delta) -> void:
	if dusty_timer <= 0:
		return
	dusty_timer -= delta
	if dusty_timer <= 0:
		dusty_timer = 0
		if not dusty_toggle:
			$Dusty.emitting = false


var framer = 0

func _process(delta):
	framer = posmod(framer - 1, 5)
	dusty_process(delta)
	
	if look_at_me:
		model.aim_turret_at(look_at_me.global_position, delta * aim_factor)
		$Targetter.global_position = look_at_me.global_position
		$Targetter.visible = true
	else:
		$Targetter.visible = false
		model.aim_turret_at(-model.turret.global_transform.basis.z, delta * aim_factor)
	
	if not player_controlled:
		return
	
	if Input.is_action_just_pressed("fire"):
		var start: Transform3D = model.get_shot_start_xform()
		var b = bs.instantiate()
		b.ignore = self
		get_parent().add_child(b)
		b.global_transform = Transform3D(start)
		
	if framer == 0:
		find_auto_target()

func _log_num(num):
	return round(num*100)/100.0

func _physics_process(delta):
	if not grounded:
		return
	
	if not player_controlled:
		return
	
	if transform.basis.y.angle_to(Vector3.UP) > PI/2.2:
		print("tipped!")
		friction_context_velocity_delta_l = Vector3.ZERO
		friction_context_velocity_delta_r = Vector3.ZERO
		return;
	
	var left_move: = 0.0
	var right_move: = 0.0

	if player_controlled:
		var try_moving: = false
		#driving = Input.get_axis("back", "forward")
		#steering = Input.get_axis("right", "left")
		var x = Input.get_axis("left", "right")
		var y = Input.get_axis("back", "forward")
		
		var drive_amount = y
		if abs(fposmod(Vector2(x, y).angle(), PI) - PI/2) < PI/3.9:
			try_moving = true
			var x_scaledown = 0.34
			var turn_factor_l = 0 if x < 0 else 1.0 + (x * x_scaledown)
			var turn_factor_r = 0 if x > 0 else 1.0 - (x * x_scaledown)
			
			left_move = drive_amount * turn_factor_l
			right_move = drive_amount * turn_factor_r
		else:
			try_moving = false
			drive_amount = x
			
			left_move = drive_amount
			right_move = -drive_amount
	
	var max_speed: = SPEED_MULT * speed
	var requested_speed_l: = max_speed * left_move
	if abs(left_move) < 0.3:
		requested_speed_l = 0
	var requested_speed_r: = max_speed * right_move
	if abs(right_move) < 0.3:
		requested_speed_r = 0
	
	var facing: = -transform.basis.z
	
#	is_driving = requested_speed != 0
#	is_reversing = requested_speed < 0
	
	var lerp_factor_l = BRAKE_LERP if requested_speed_l == 0 else acceleration_factor * CONST_ACCEL_MUL
	var old_tread_l = tread_linear_velocty_l
	tread_linear_velocty_l = lerp(tread_linear_velocty_l, requested_speed_l, lerp_factor_l * delta)
	
	var lerp_factor_r = BRAKE_LERP if requested_speed_r == 0 else acceleration_factor * CONST_ACCEL_MUL
	var old_tread_r = tread_linear_velocty_r
	tread_linear_velocty_r = lerp(tread_linear_velocty_r, requested_speed_r, lerp_factor_r * delta)
	
	var min_brake = MIN_BRAKE_EFFECT * delta
	if requested_speed_l == 0 and abs(old_tread_l - tread_linear_velocty_l) < min_brake:
		tread_linear_velocty_l = old_tread_l - (sign(tread_linear_velocty_l) * min_brake)
		if sign(tread_linear_velocty_l) != sign(old_tread_l):
			tread_linear_velocty_l = 0.0
	if requested_speed_r == 0 and abs(old_tread_r - tread_linear_velocty_r) < min_brake:
		tread_linear_velocty_r = old_tread_r - (sign(tread_linear_velocty_r) * min_brake)
		if sign(tread_linear_velocty_r) != sign(old_tread_r):
			tread_linear_velocty_r = 0.0
	
	var avg_frict_context = (friction_context_velocity_delta_l + friction_context_velocity_delta_r)/2.0
	var tread_static_terrain_diff = (linear_velocity + avg_frict_context).length()
	
	if tread_static_terrain_diff > 1:
		dusty_on()
	else:
		dusty_off()
	if linear_velocity.length() > 3:
		$LilDusty.emitting = true
	else:
		$LilDusty.emitting = false
	
	friction_context_velocity_delta_l = (-facing) * tread_linear_velocty_l
	friction_context_velocity_delta_r = (-facing) * tread_linear_velocty_r
#	if player_controlled and framer == 0:
#		#print(round(tread_linear_velocty/10.0)*10)
#		print(round(tread_static_terrain_diff*10.0)/10.0, ' ', round(linear_velocity.length()*10.0)/10.0)

#func _integrate_forces(state: PhysicsDirectBodyState3D):
#	var delta = state.step
#
#	var turn_strength = drive_turn if is_driving else stationary_turn
#	if is_reversing:
#		turn_strength *= -1
#
#	var turning_force = steering * PI * turn_strength * CONST_ROTATION_MUL * delta
#	var projected_ang_vel = angular_velocity.project(transform.basis.y)
#	var existing_ang_vel = projected_ang_vel.dot(transform.basis.y) * projected_ang_vel.length()
#	var max_vel = MAX_MOVING_TURN_VELOCITY if is_driving else MAX_TURN_VELOCITY
#	var new_ang_vel = clampf(existing_ang_vel + turning_force, -max_vel, max_vel)
#	#state.angular_velocity += transform.basis.y * (new_ang_vel - existing_ang_vel)
#	state.angular_velocity += transform.basis.y * (turning_force/2.0)
#	if player_controlled and framer == 0:
#		print(new_ang_vel - existing_ang_vel, ' ', turning_force)
#	#angular_velocity.y = steering * PI * turn_strength * CONST_ROTATION_MUL
#
