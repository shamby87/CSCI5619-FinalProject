extends Node3D

@export var max_speed:= 2.5
@export var dead_zone := 0.2

@export var smooth_turn_speed:= 45.0
@export var smooth_turn_dead_zone := 0.2

var input_vector:= Vector2.ZERO

var hand_steer = false
var snap_turn = false

var can_snap = true

var xr_interface: XRInterface

var camera: XRCamera3D
var previous_pos: Vector3
var previous_rot = 0

var translation_gain = 0.5
var valid_movement = 0.15

var rotation_gain = 0 # 0 means no rotation gain, 1 means double rotation (e.g physical 90* is virtual 180*), 2 triple, etc.
var target_rotation = 0
var rotations = 0
var rotation_threshold = 0.05

var bounds = []
var targets = []
var cur_target = 0

var red_threshold = 0.25
var stop_threshold = 0.1

var avoid_boundary = false
var still_turning = false
var just_rotated = false
var cur_bound = null

var already_moved = false

func _ready():
	self.camera = find_child('XRCamera3D') 

	for bound in self.find_child('WorldBounds').get_children():
		self.bounds.append(bound.position)	
	
	for targ in %Targets.get_children():
		self.targets.append(targ.position)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	# # Forward translation
	# if self.input_vector.y > self.dead_zone || self.input_vector.y < -self.dead_zone:
	# 	var movement_vector = Vector3(0, 0, max_speed * -self.input_vector.y * _delta)
		
	# 	if !hand_steer: # Move in direction of camera
	# 		self.position += movement_vector.rotated(Vector3.UP, $XRCamera3D.global_rotation.y)
	# 	else:
	# 		self.position += movement_vector.rotated(Vector3.UP, $RightController.global_rotation.y)

	# Once the camera's position is set at the start, move to the start point and face the first target
	if !already_moved && self.camera.position.x != 0 && self.camera.position.z != 0:
		var delta = self.camera.global_position - %Start.global_position
		delta.y = 0
		self.translate(-delta)

		# Look the camera at the start to get the delta, then move it back so we can rotate the origin
		var prev_rot = self.camera.rotation
		self.camera.look_at(self.targets[0])
		var delta_rot = self.camera.rotation.y - prev_rot.y
		self.camera.rotation = prev_rot

		# Now face the first target
		self.translate(self.camera.position)
		self.rotate(Vector3.UP, delta_rot)
		self.translate(self.camera.position * -1)

		# Only want to do this once at the beginning
		already_moved = true

	# Translation gain
	var current_pos = self.camera.position
	var delta_pos = current_pos - self.previous_pos
	
	if translation_gain > 0:
		# If there was sufficient movement in the x direction, then do the translation gain
		if abs(delta_pos.x) > valid_movement:
			delta_pos.x *= translation_gain
		# Z direction too
		if abs(delta_pos.z) > valid_movement:
			delta_pos.z *= translation_gain
		delta_pos.y = 0 # Don't want any vertical gain

		self.translate(delta_pos)
	self.previous_pos = current_pos
	
	# Rotation gain
	var current_rot = self.camera.rotation.y
	var delta_rot = 0

	# The rotation goes from 179.999 to -179.999 degrees, so we handle that with special cases
	if current_rot > (PI - 0.1) && previous_rot < (-PI + 0.1):
		delta_rot = -((PI - current_rot) + (previous_rot + PI))
	elif previous_rot > (PI - 0.1) && current_rot < (-PI + 0.1):
		delta_rot = (PI - previous_rot) + (current_rot + PI)
	else: # normal case, just subtract the previous rotation from the current rotation
		delta_rot = current_rot - previous_rot

	# Rotate the origin by the change in rotation times the gain
	if rotation_gain > 0:
		# move to the position of the camera
		self.translate(self.camera.position)

		# rotate about the camera's position
		self.rotate(Vector3.UP, delta_rot * rotation_gain)

		# reverse the translation to move back to the original position
		self.translate(self.camera.position * -1)

	self.previous_rot = current_rot

	# See if we are hitting any of the boundaries
	for bound in self.bounds:
		bound.y = self.camera.position.y

		# Check all bounds, unless we are currently dealing with a bound we are about to hit
		if cur_bound == null || cur_bound.distance_to(bound) < 0.1:
			var distance = self.camera.position.distance_to(bound)
			
			# Start turning the screen red if we are close to the boundary
			if distance < red_threshold:
				cur_bound = bound
				# Make the screen red, more red as you get closer to the bounds
				%RedScreen.color.a = 0.8 * ((red_threshold - distance) / red_threshold)
			
				# If we hit the boundary, start turning
				if distance < stop_threshold || (avoid_boundary && !still_turning):
					# %StopSign.visible = true
					avoid_boundary = true
			else:
				cur_bound = null

	# If we are at a boundary, redirect the user in the direction most optimal to continue walking
	if avoid_boundary and !still_turning:
		face_next_target()
	
	# If we are currently turning around, check if we are now facing the correct direction
	if still_turning:
		# See if we are facing the right direction with some fuzz
		if abs(self.camera.rotation.y - self.target_rotation) < rotation_threshold:
			if !self.just_rotated:
				# Might need to do several rotations
				self.just_rotated = true
				self.rotations -= 1
				if self.rotations <= 0:
					# Done rotating, stop the rotation gain
					self.still_turning = false
					rotation_gain = 0
					self.avoid_boundary = false
					%TurnSign.visible = false
					%LeftTurn.visible = false
					%RightTurn.visible = false
		else:
			self.just_rotated = false
	else:
		self.avoid_boundary = false
		%TurnSign.visible = false
		%LeftTurn.visible = false
		%RightTurn.visible = false


# Checks if 2 line segments intersect each other. All 4 args are Vector2s
# This was based on the math and python code here: https://www.geeksforgeeks.org/check-if-two-given-line-segments-intersect/
func segments_intersect(seg1_start, seg1_end, seg2_start, seg2_end):
	# Check the relative orientation of the 3 points. Returns 0 for collinear, 1 for clockwise, and 2 for counterclockwise
	var orientation = func(p, q, r):
		var val = (q[1] - p[1]) * (r[0] - q[0]) - (q[0] - p[0]) * (r[1] - q[1])
		if val == 0:
			return 0  # collinear
		return 1 if val > 0 else 2  # clock or counterclock wise

	# Check if point q is on the line segment between p and r
	var on_segment = func(p, q, r):
		return (
			(q[0] <= max(p[0], r[0]) and q[0] >= min(p[0], r[0])) and
			(q[1] <= max(p[1], r[1]) and q[1] >= min(p[1], r[1]))
		)

	# Get the 4 different orientations needed
	var o1 = orientation.call(seg1_start, seg1_end, seg2_start)
	var o2 = orientation.call(seg1_start, seg1_end, seg2_end)
	var o3 = orientation.call(seg2_start, seg2_end, seg1_start)
	var o4 = orientation.call(seg2_start, seg2_end, seg1_end)

	# General case
	if o1 != o2 and o3 != o4:
		return true
	
	# Special cases for collinear segments
	if o1 == 0 and on_segment.call(seg1_start, seg2_start, seg1_end):
		return true
	if o2 == 0 and on_segment.call(seg1_start, seg2_end, seg1_end):
		return true
	if o3 == 0 and on_segment.call(seg2_start, seg1_start, seg2_end):
		return true
	if o4 == 0 and on_segment.call(seg2_start, seg1_end, seg2_end):
		return true

	return false

func intersects_bounds(line_start, line_end):
	# Check every edge on the bounds to see if this line intersects any
	for i in self.bounds.size():
		# Get the line segment from this bound to the next bound
		# Again, we ignore the y value and treat this as a line in 2D space
		var edge_start = Vector2(self.bounds[i].x, self.bounds[i].z)
		var edge_end = Vector2(self.bounds[(i + 1) % self.bounds.size()].x, self.bounds[(i + 1) % self.bounds.size()].z)

		# Don't try to check intersections with itself
		if edge_start == line_end or edge_end == line_end:
			continue

		if segments_intersect(line_start, line_end, edge_start, edge_end):
			return true
	
	# If no intersections anywhere, return false
	return false

func find_best_direction():
	var current_pos = self.camera.position
	var max_dist = 0
	var max_i = -1

	# Check which bound is furthest away from the player
	for i in self.bounds.size():
		var distance = self.camera.position.distance_to(self.bounds[i])
		if distance > max_dist:
			# Check if this is a valid direction that does not cut through the bounds at all
			# We will ignore the y values, treat as a 2d vector (XZ-plane)
			if !intersects_bounds(Vector2(current_pos.x, current_pos.z), Vector2(self.bounds[i].x, self.bounds[i].z)):
				max_dist = distance
				max_i = i

	return self.bounds[max_i]

func face_next_target():
	%TurnSign.visible = true
	var bound = find_best_direction()
	var distance = self.camera.position.distance_to(bound)
	
	# This line mesh is for debugging purposes, it points at the selected boundary point
	var line_mesh = %Pointer.find_child('MeshInstance3D')
	line_mesh.scale.z = distance
	line_mesh.position = (self.camera.position + bound) / 2.0
	line_mesh.position.y -= 0.5
	line_mesh.look_at(self.to_global(bound), Vector3.UP)
	
	# Want the camera rotation to be the same as the line_mesh pointing at the selected boundary
	self.target_rotation = line_mesh.rotation.y

	# Find how much we need to rotate around the y axis in the physical world to point at bound (in radians)
	var rot_amt = self.camera.rotation.y - self.target_rotation
	
	# Which direction should the user turn physically
	var dir = rot_amt / abs(rot_amt) # -1 for counterclockwise, 1 for clockwise
	if dir < 0:
		%LeftTurn.visible = true
	if dir > 0:
		%RightTurn.visible = true

	rot_amt = abs(rot_amt)

	# Point the mesh at the target and find how much we need to rotate in the virtual world to face the current target
	var line_mesh2 = %Pointer2.find_child('MeshInstance3D')
	line_mesh2.scale.z = self.camera.global_position.distance_to(self.targets[self.cur_target])
	line_mesh2.global_position = (self.camera.global_position + self.targets[self.cur_target]) / 2.0
	line_mesh2.position.y -= 0.5
	line_mesh2.look_at(self.targets[self.cur_target], Vector3.UP)
	var cur_target_dir = self.camera.rotation.y - line_mesh2.rotation.y

	# If target and bound are in different rotation directions, flip target direction
	if (cur_target_dir < 0 && dir > 0) || (cur_target_dir > 0 && dir < 0):
		cur_target_dir *= -1
	
	# To help prevent motion sickness, make sure we aren't rotating at more than 50% gain
	self.rotations = 0
	while self.rotations < 6: # Need some limit here
		# We want to rotate in the real world by some multiple of 360* to be facing the same current target
		var rot_scale = 0

		# We might need to rotate in the virtual world multiple times too
		for i in range(0, 4):
			rot_scale = (cur_target_dir + i*2*PI) / (rot_amt + 2*PI*self.rotations) # Virtual rot amount / physical rotation amount
			
			# Valid rotation
			if rot_scale >= 1 && rot_scale <= 1.5:
				break
				
		rotation_gain = rot_scale - 1
		self.rotations += 1

		# Once we are below 50%, we can break
		if rotation_gain <= 0.5 && rotation_gain >= 0:
			# print("rot_amt: %f, rot_scale: %f, rotation_gain: %f" % [rot_amt, rot_scale, rotation_gain])
			break
			
	# print("rot_amt: %f, rotation_gain: %f, rotations: %d" % [rot_amt, rotation_gain, self.rotations])
	avoid_boundary = false
	still_turning = true

func handle_collision(body: Node3D):
	if body.name.contains("Target"):
		cur_target += 1
		if cur_target < self.targets.size():
			face_next_target()
			body.name = "Hit%d" % cur_target
