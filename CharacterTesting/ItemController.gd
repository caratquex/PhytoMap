# Attach this script to the main UI Node (e.g., Control, Panel)

extends Control

# --- Export Variables for Weapons (Existing) ---
@export var grenade_button: TextureButton
@export var gun_button: TextureButton
@export var shovel_button: TextureButton

# --- Export Variables for Bars (NEW) ---
@export var bullet_bar: TextureProgressBar
@export var grenade_bar: TextureProgressBar

# --- Constants (NEW) ---
# Set the maximum possible value for the bars
const MAX_AMMO: int = 5 
# Define the input action for the mouse click
#const MOUSE_CLICK_ACTION = "primary_attack" # Ensure this is mapped to Left Mouse Button in Project Settings

# Function to deselect all buttons except the one being activated
func _deselect_all_except(active_button: TextureButton):
	var all_buttons = [gun_button, grenade_button, shovel_button]
	
	for button in all_buttons:
		if button != active_button and button.is_pressed():
			button.set_pressed(false)

# Called when the node enters the scene tree for the first time.
func _ready():
	if !grenade_button or !gun_button or !shovel_button or !bullet_bar or !grenade_bar:
		push_error("One or more UI node references are missing! Please assign all export variables in the Inspector.")
		return
	
	# --- NEW: Bar Initialization ---
	# 1. The bar should be full on default.
	bullet_bar.max_value = MAX_AMMO
	bullet_bar.value = MAX_AMMO
	
	grenade_bar.max_value = MAX_AMMO
	grenade_bar.value = MAX_AMMO
	
	# Set the Gun as the default selection and enforce exclusion immediately.
	gun_button.set_pressed(true)
	_deselect_all_except(gun_button)

# --- NEW: Input Function for Mouse Clicks ---
#func _input(event):
	## Check if the event is the left mouse click (Primary Attack)
	#if event.is_action_pressed(MOUSE_CLICK_ACTION):
		#
		## 2. When select "1" (Gun), click left mouse, Bullet Bar value decrease by 1
		#if gun_button.is_pressed():
			#if bullet_bar.value > 0:
				#bullet_bar.value -= 1
				#print("Gun fired! Bullet Ammo: ", bullet_bar.value)
			#else:
				#print("Click! Bullet Bar empty.")
				#
		## 3. When select "2" (Grenade), click left mouse, Grenade Bar value decrease by 1
		#elif grenade_button.is_pressed():
			#if grenade_bar.value > 0:
				#grenade_bar.value -= 1
				#print("Grenade used! Grenade Ammo: ", grenade_bar.value)
			#else:
				#print("Click! Grenade Bar empty.")
				#
		## We're only consuming input if a valid action was performed
		#get_tree().set_input_as_handled()


# Called every frame to process input (Existing Keyboard Logic)
func _process(delta):
	
	# --- Input Mapping ---
	
	# 1 Key: Select Gun (Toggles the button state)
	if Input.is_action_just_pressed("gun"):
		gun_button.set_pressed(!gun_button.is_pressed())
		_deselect_all_except(gun_button)

	# 2 Key: Select Grenade (Toggles the button state)
	elif Input.is_action_just_pressed("grenade"):
		grenade_button.set_pressed(!grenade_button.is_pressed())
		_deselect_all_except(grenade_button)
		
	# 3 Key: Select Shovel (Toggles the button state)
	elif Input.is_action_just_pressed("shovel"):
		shovel_button.set_pressed(!shovel_button.is_pressed())
		_deselect_all_except(shovel_button)
