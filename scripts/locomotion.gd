extends Node3D

@export var max_speed:= 2.5
@export var dead_zone := 0.2

@export var smooth_turn_speed:= 45.0
@export var smooth_turn_dead_zone := 0.2

var input_vector:= Vector2.ZERO

var hand_steer = false
var snap_turn = false

var can_snap = true

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):

	# Forward translation
	if self.input_vector.y > self.dead_zone || self.input_vector.y < -self.dead_zone:
		var movement_vector = Vector3(0, 0, max_speed * -self.input_vector.y * delta)
		
		if !hand_steer: # Move in direction of camera
			self.position += movement_vector.rotated(Vector3.UP, $XRCamera3D.global_rotation.y)
		else:
			self.position += movement_vector.rotated(Vector3.UP, $RightController.global_rotation.y)


	if !snap_turn: # Smooth turn
		if self.input_vector.x > self.smooth_turn_dead_zone || self.input_vector.x < -self.smooth_turn_dead_zone:
			
			# move to the position of the camera
			self.translate($XRCamera3D.position)

			# rotate about the camera's position
			self.rotate(Vector3.UP, deg_to_rad(smooth_turn_speed) * -self.input_vector.x * delta)

			# reverse the translation to move back to the original position
			self.translate($XRCamera3D.position * -1)
	else:
		if abs(self.input_vector.x) > 0.9 && can_snap: # If the thumbstick is almost all the way left/right
			# Don't snap again until the controller moves back to the center
			can_snap = false

			# move to the position of the camera
			self.translate($XRCamera3D.position)

			# rotate about the camera's position by 45 degrees (with the sign of the thumbstick direction)
			self.rotate(Vector3.UP, deg_to_rad(45) * (-self.input_vector.x / abs(self.input_vector.x)))

			# reverse the translation to move back to the original position
			self.translate($XRCamera3D.position * -1)
		elif abs(self.input_vector.x) < dead_zone:
			# If we have come back to the dead zone, we can snap again
			can_snap = true


func process_input(input_name: String, input_value: Vector2):
	if input_name == "primary":
		input_vector = input_value

func button_pressed(name: String):
	if name == "ax_button":
		self.hand_steer = !self.hand_steer # Toggle hand-directed steering
	if name == "by_button":
		self.snap_turn = !self.snap_turn # Toggle snap turn mode

func handle_collision(body: Node3D):
	if body.name.contains("Obstacle"):
		# If we hit an obstacle, move back to center
		self.position.x = 0
		self.position.z = 0
	elif body.name.contains("Target"):
		# If we hit a target, remove it from the scene
		body.get_parent().remove_child(body) 