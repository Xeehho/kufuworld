extends Node2D

const NPC_SCENE = preload("res://scenes/npc.tscn")

var npc_list: Array = []
var interaction_ui: Control = null
var current_target: CharacterBody2D = null

var npc_configs = [
	{"id":"npc_001","name":"谢云鹤","personality":"儒雅","npc_type":"scholar","pos":Vector2(300,300)},
	{"id":"npc_002","name":"铁三娘","personality":"豪爽","npc_type":"warrior","pos":Vector2(500,450)},
	{"id":"npc_003","name":"柳如烟","personality":"阴沉","npc_type":"mysterious","pos":Vector2(700,350)},
	{"id":"npc_004","name":"老樵夫","personality":"慈悲","npc_type":"elder","pos":Vector2(350,550)},
]

func _ready():
	_spawn_npcs()
	_init_interaction_ui()

func _spawn_npcs():
	for cfg in npc_configs:
		var npc = NPC_SCENE.instantiate()
		npc.global_position = cfg["pos"]
		npc.name = cfg["name"]
		npc.npc_type = cfg.get("npc_type", "warrior")
		npc.npc_data = _create_npc_data(cfg)
		add_child(npc)
		npc_list.append(npc)

func _create_npc_data(cfg: Dictionary) -> NPCData:
	var nd = NPCData.new()
	nd.npc_id = cfg["id"]
	nd.npc_name = cfg["name"]
	nd.personality = cfg["personality"]
	var all_likes = ["茶","酒","剑","书","花","棋","武学","美食","金钱","山水"]
	nd.likes = [all_likes[hash(cfg["id"]) % all_likes.size()]]
	nd.dislikes = [all_likes[(hash(cfg["id"]) + 3) % all_likes.size()]]
	nd.home_position = cfg["pos"]
	nd.work_position = cfg["pos"] + Vector2(randi_range(-80,80), randi_range(-50,50))
	return nd

func _init_interaction_ui():
	interaction_ui = Control.new()
	interaction_ui.name = "InteractionUI"
	interaction_ui.visible = false
	interaction_ui.set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	interaction_ui.add_child(bg)

	var center = Control.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.custom_minimum_size = Vector2(300, 300)
	interaction_ui.add_child(center)

	var options = ["交谈", "送礼", "切磋", "观察", "邀请", "离开"]
	var angles = [0, 60, 120, 180, 240, 300]
	for i in range(6):
		var btn = _make_ring_button(options[i], angles[i], center)
		btn.pressed.connect(_on_option_pressed.bind(i))

	get_node("/root/Main/World/UI").add_child(interaction_ui)
	print("[NPCSpawner] Interaction UI created, NPCs spawned: " + str(npc_list.size()))

func _make_ring_button(text_str: String, angle_deg: float, parent: Control) -> Button:
	var btn = Button.new()
	btn.text = text_str
	btn.size = Vector2(70, 32)
	var rad = deg_to_rad(angle_deg)
	var radius = 100
	btn.position = Vector2(150 + cos(rad) * radius - 35, 150 + sin(rad) * radius - 16)
	btn.theme_type_variation = "Button"
	parent.add_child(btn)
	return btn

func _on_option_pressed(index: int):
	match index:
		0: _handle_talk()
		1: _handle_gift()
		2: _handle_spar()
		3: _handle_observe()
		4: _handle_invite()
		5: _handle_leave()
	hide_interaction_ui()

func _handle_talk():
	if current_target:
		var nd = current_target.npc_data
		print("[Interact] 与" + nd.npc_name + "交谈 - 性格:" + nd.personality)
		var favor = GameManager.get_relation(nd.npc_name, "玩家")
		GameManager.modify_relation(nd.npc_name, "玩家", 2.0, "neutral")
		if favor > 50:
			DialogManager.show_dialog(nd.npc_name, ["少侠，今日风光明媚，不如对饮一杯？"])
		elif favor < -20:
			DialogManager.show_dialog(nd.npc_name, ["哼，你我之间没什么好说的。"])

func _handle_gift():
	if current_target:
		var nd = current_target.npc_data
		print("[Interact] 向" + nd.npc_name + "送礼")
		GameManager.modify_relation(nd.npc_name, "玩家", 10.0, "neutral")

func _handle_spar():
	if current_target:
		var nd = current_target.npc_data
		print("[Interact] 与" + nd.npc_name + "切磋")
		GameManager.modify_relation(nd.npc_name, "玩家", -5.0, "neutral")

func _handle_observe():
	if current_target:
		var nd = current_target.npc_data
		print("[Interact] 观察" + nd.npc_name)
		DialogManager.show_dialog(nd.npc_name, [
			"性格:" + nd.personality + "  喜好:" + str(nd.likes),
			"好感度:" + str(GameManager.get_relation(nd.npc_name, "玩家"))
		])

func _handle_leave():
	if current_target and current_target.has_method("set_interacting"):
		current_target.set_interacting(false)
	current_target = null

func _handle_invite():
	if current_target and current_target.npc_data:
		var nd = current_target.npc_data
		var favor = GameManager.get_relation(nd.npc_name, "玩家")
		if favor < 30:
			DialogManager.show_dialog(nd.npc_name, ["你我缘分未到，日后再谈..."])
			return
		if GameManager.invite_npc(nd.npc_name):
			DialogManager.show_dialog(nd.npc_name, ["承蒙不弃，愿随少侠前往!"])
			var npc_script = current_target as Node
			if npc_script and npc_script.has_method("set_homestead"):
				npc_script.set_homestead(true)
		else:
			DialogManager.show_dialog(nd.npc_name, ["我已在贵府安顿，不必再邀。"])


func show_interaction_ui(npc: CharacterBody2D):
	current_target = npc
	interaction_ui.visible = true

func hide_interaction_ui():
	if current_target and current_target.has_method("set_interacting"):
		current_target.set_interacting(false)
	interaction_ui.visible = false
	current_target = null
