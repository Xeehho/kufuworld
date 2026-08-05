extends Node2D

const NPC_SCENE = preload("res://scenes/npc.tscn")
const TextureGen = preload("res://scripts/texture_generator.gd")

var npc_list: Array = []
var interaction_ui: Control = null
var current_target: CharacterBody2D = null

var npc_configs = [
	{"id":"npc_001","name":"谢云鹤","personality":"儒雅","npc_type":"scholar","pos":Vector2(300,300)},
	{"id":"npc_002","name":"铁三娘","personality":"豪爽","npc_type":"warrior","pos":Vector2(500,450)},
	{"id":"npc_003","name":"柳如烟","personality":"阴沉","npc_type":"mysterious","pos":Vector2(700,350)},
	{"id":"npc_004","name":"老樵夫","personality":"慈悲","npc_type":"elder","pos":Vector2(350,550)},
	# 大世界扩展NPC（分布各地，配合120瓦片半径地图）
	{"id":"npc_005","name":"少林慧空","personality":"刚正","npc_type":"warrior","pos":Vector2(-620,320)},
	{"id":"npc_006","name":"武当清虚","personality":"儒雅","npc_type":"scholar","pos":Vector2(420,220)},
	{"id":"npc_007","name":"北境猎人","personality":"豪爽","npc_type":"warrior","pos":Vector2(-900,-500)},
	{"id":"npc_008","name":"江南沈万","personality":"精明","npc_type":"merchant","pos":Vector2(900,600)},
	{"id":"npc_009","name":"南山隐士","personality":"慈悲","npc_type":"elder","pos":Vector2(-300,800)},
	{"id":"npc_010","name":"东海渔夫","personality":"豪爽","npc_type":"elder","pos":Vector2(1200,-300)},
	{"id":"npc_011","name":"西域刀客","personality":"阴沉","npc_type":"warrior","pos":Vector2(-1200,100)},
	{"id":"npc_012","name":"雪山道姑","personality":"阴沉","npc_type":"mysterious","pos":Vector2(600,-800)},
]

func _ready():
	_spawn_npcs()
	_init_interaction_ui()

func _spawn_npcs():
	# NPC出生点校验：硬编码坐标可能落在水面/山体/河对岸孤岛，
	# 必须通过世界生成器的可达性洪泛校验，不可达则自动搬迁到最近可达瓦片
	var wg = get_node_or_null("../WorldGenerator")
	for cfg in npc_configs:
		var pos: Vector2 = cfg["pos"]
		if wg and wg.has_method("is_world_pos_reachable") and not wg.is_world_pos_reachable(pos):
			var new_pos: Vector2 = wg.find_nearest_reachable(pos)
			print("[NPCSpawner] ", cfg["name"], " 原位置不可达，搬迁 ", pos, " -> ", new_pos)
			pos = new_pos
			cfg["pos"] = pos
		var npc = NPC_SCENE.instantiate()
		npc.global_position = pos
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
	interaction_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 半透明背景（点击关闭）
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: hide_interaction_ui())
	interaction_ui.add_child(bg)

	# 居中面板（锚点居中，适配任意分辨率）
	var panel = Panel.new()
	panel.name = "InteractPanel"
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(true))
	UITheme.center_panel(panel, 460, 330)
	interaction_ui.add_child(panel)

	# 标题：NPC名字
	var name_lbl = Label.new()
	name_lbl.name = "NameLabel"
	name_lbl.position = Vector2(0, 12)
	name_lbl.size = Vector2(460, 26)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_title(name_lbl, 18)
	panel.add_child(name_lbl)

	# 金色分隔线
	var div = ColorRect.new()
	div.color = UITheme.GOLD_DIM
	div.position = Vector2(24, 44)
	div.size = Vector2(412, 1)
	panel.add_child(div)

	# 左侧：NPC头像框
	var avatar_bg = Panel.new()
	avatar_bg.position = Vector2(30, 62)
	avatar_bg.size = Vector2(116, 116)
	avatar_bg.add_theme_stylebox_override("panel", UITheme.inset_style())
	panel.add_child(avatar_bg)
	var avatar = TextureRect.new()
	avatar.name = "Avatar"
	avatar.position = Vector2(6, 6)
	avatar.size = Vector2(104, 104)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	avatar_bg.add_child(avatar)

	# 左侧：性格/好感度信息
	var info_lbl = Label.new()
	info_lbl.name = "InfoLabel"
	info_lbl.position = Vector2(24, 186)
	info_lbl.size = Vector2(130, 100)
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_label(info_lbl, 12, UITheme.TEXT_DIM)
	panel.add_child(info_lbl)

	# 右侧：选项按钮列表
	var options = ["交谈", "送礼", "切磋", "观察", "邀请", "离开"]
	for i in range(6):
		var btn = Button.new()
		btn.text = options[i]
		btn.position = Vector2(180, 58 + i * 42)
		btn.size = Vector2(240, 34)
		UITheme.style_button(btn, 15)
		btn.pressed.connect(_on_option_pressed.bind(i))
		panel.add_child(btn)

	# 底部提示
	var hint = Label.new()
	hint.text = "ESC 关闭"
	hint.position = Vector2(0, 300)
	hint.size = Vector2(460, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(hint, 10, UITheme.TEXT_DIM)
	panel.add_child(hint)

	get_node("/root/Main/World/UI").add_child(interaction_ui)
	print("[NPCSpawner] Interaction UI created, NPCs spawned: " + str(npc_list.size()))

func is_interaction_open() -> bool:
	return interaction_ui != null and interaction_ui.visible

func _unhandled_input(event):
	if is_interaction_open() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide_interaction_ui()
		get_viewport().set_input_as_handled()

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
	var panel = interaction_ui.get_node_or_null("InteractPanel")
	if panel == null:
		interaction_ui.visible = true
		return
	var name_lbl = panel.get_node_or_null("NameLabel")
	if name_lbl and npc.npc_data:
		name_lbl.text = npc.npc_data.npc_name
	# 填充NPC头像（取idle_down首帧）
	var avatar = panel.get_node_or_null("Avatar")
	if avatar and npc.npc_data:
		avatar.texture = TextureGen.load_png_texture("res://sprites/npc/%s_idle_down_0.png" % npc.npc_type)
	# 填充性格/好感度
	var info_lbl = panel.get_node_or_null("InfoLabel")
	if info_lbl and npc.npc_data:
		var favor = GameManager.get_relation(npc.npc_data.npc_name, "玩家")
		info_lbl.text = "性格：" + npc.npc_data.personality + "\n好感：" + str(int(favor))
	interaction_ui.visible = true
	# 面板淡入缩放动画
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.92, 0.92)
	panel.pivot_offset = panel.size / 2
	var tween = interaction_ui.create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.15)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_interaction_ui():
	if current_target and current_target.has_method("set_interacting"):
		current_target.set_interacting(false)
	interaction_ui.visible = false
	current_target = null
