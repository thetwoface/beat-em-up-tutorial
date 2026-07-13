class_name Character
extends CharacterBody2D

const GRAVITY:= 600.0

@export var max_health: int
@export var damage: int
@export var damage_power: int
@export var speed: float
@export var jump_intensity: float
@export var knockback_intensity: float
@export var knockdown_intensity: float
@export var duration_grounded: float
@export var can_respawn: bool

@onready var animation_player:= $AnimationPlayer
@onready var character_sprite:= $CharacterSprite
@onready var damage_emitter:= $DamageEmitter
@onready var damage_receiver: DamageReceiver = $DamageReceiver
@onready var collision_shape:= $CollisionShape2D

enum State {IDLE, WALK, ATTACK, TAKEOFF, JUMP, LAND, JUMPKICK, HURT, FALL, GROUNDED, DEATH}

var anim_attacks:= ["punch", "punch_alt", "kick", "roundkick"]
var attack_combo_index:= 0

var anim_map: Dictionary = {
	State.IDLE: "idle",
	State.WALK: "walk",
	
	State.ATTACK: "punch",
	State.JUMPKICK: "jumpkick",
	
	State.TAKEOFF: "takeoff",
	State.JUMP: "jump",
	State.LAND: "land",
	
	State.HURT: "hurt",
	State.FALL: "fall",
	State.GROUNDED: "grounded",
	State.DEATH: "grounded",
}

var state = State.IDLE
var height:= 0.0
var height_speed:= 0.0
var current_health:= 0
var time_sinse_grounded:= Time.get_ticks_msec()
var is_last_hit_successful:= false

func _ready() -> void:
	damage_emitter.area_entered.connect(on_emit_damage.bind())
	damage_receiver.damage_received.connect(on_receive_damage.bind())
	current_health = max_health

func _process(delta: float) -> void:
	handle_input()
	handle_movement()
	handle_animations()
	handle_air_time(delta)
	handle_grounded()
	handle_death(delta)
	flip_sprites()
	
	character_sprite.position = Vector2.UP * height
	collision_shape.disabled = is_collision_enabled()
	
	move_and_slide()

func handle_movement() -> void:
	if can_move():
		if velocity.length() == 0:
			state = State.IDLE
		else:
			state = State.WALK

func handle_input() -> void:
	pass

func handle_animations() -> void:
	if state == State.ATTACK:
		animation_player.play(anim_attacks[attack_combo_index])
	elif(animation_player.has_animation(anim_map[state])):
		animation_player.play(anim_map[state])

func handle_air_time(delta: float) -> void:
	if [State.JUMP, State.JUMPKICK, State.FALL].has(state):
		height += height_speed * delta
		if height < 0:
			height = 0
			if state == State.FALL:
				state = State.GROUNDED
				time_sinse_grounded = Time.get_ticks_msec()
			else:
				state = State.LAND
			velocity = Vector2.ZERO
		else:
			height_speed -= GRAVITY * delta

func handle_grounded() -> void:
	if state == State.GROUNDED and (Time.get_ticks_msec() - time_sinse_grounded > duration_grounded):
		if current_health <= 0:
			state = State.DEATH
		else:
			state = State.LAND

func handle_death(delta: float) -> void:
	if state == State.DEATH and not can_respawn:
		modulate.a -= delta / 2.0
		if modulate.a <= 0:
			queue_free()

func flip_sprites() -> void:
	if velocity.x > 0:
		character_sprite.flip_h = false
		damage_emitter.scale.x = 1
	elif velocity.x < 0:
		character_sprite.flip_h = true
		damage_emitter.scale.x = -1

func can_attack() -> bool:
	return state == State.IDLE or state == State.WALK

func can_jumpkick() -> bool:
	return state == State.JUMP

func can_jump() -> bool:
	return state == State.IDLE or state == State.WALK

func can_move() -> bool:
	return state == State.IDLE or state == State.WALK

func can_get_hurt() -> bool:
	return [State.IDLE, State.WALK, State.TAKEOFF, State.JUMP, State.LAND].has(state)

func is_collision_enabled() -> bool:
	return [State.GROUNDED, State.DEATH].has(state)

func on_action_complete() -> void:
	state = State.IDLE

func on_takeoff_complete() -> void:
	state = State.JUMP
	height_speed = jump_intensity

func on_land_complete() -> void:
	state = State.IDLE

func on_emit_damage(receiver: DamageReceiver) -> void:
	var hit_type:= DamageReceiver.HitType.NORMAL
	var direction:= Vector2.LEFT if receiver.global_position.x < global_position.x else Vector2.RIGHT
	var current_damage = damage
	
	if state == State.JUMPKICK:
		hit_type = DamageReceiver.HitType.KNOCKDOWN
	
	if attack_combo_index == anim_attacks.size() - 1:
		hit_type = DamageReceiver.HitType.POWER
		current_damage = damage_power
	
	receiver.damage_received.emit(current_damage, direction, hit_type)
	is_last_hit_successful = true

func on_receive_damage(damage_amount: int, direction: Vector2, hit_type:DamageReceiver.HitType) -> void:
	if can_get_hurt():
		current_health = clamp(current_health - damage_amount, 0, max_health)
		
		if current_health == 0 or hit_type == DamageReceiver.HitType.KNOCKDOWN:
			state = State.FALL
			height_speed = knockdown_intensity
		else:
			state = State.HURT
			
		velocity = knockback_intensity * direction
