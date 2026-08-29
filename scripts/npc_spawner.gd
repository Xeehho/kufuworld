extends Node2D

const NPC_SCENE = preload("res://scenes/npc.tscn")
const TextureGen = preload("res://scripts/texture_generator.gd")

var npc_list: Array = []
var interaction_ui: Control = null
var current_target: CharacterBody2D = null

# 野外NPC（门派弟子/隐士/散人）：坐标为世界像素，不可达时自动搬迁
var npc_configs = [
	{"id":"npc_001","name":"谢云鹤","personality":"儒雅","npc_type":"scholar","pos":Vector2(300,300)},
	{"id":"npc_003","name":"柳如烟","personality":"阴沉","npc_type":"mysterious","pos":Vector2(700,350)},
	{"id":"npc_004","name":"老樵夫","personality":"慈悲","npc_type":"elder","pos":Vector2(350,550)},
	{"id":"npc_005","name":"少林慧空","personality":"刚正","npc_type":"warrior","pos":Vector2(-620,320)},
	{"id":"npc_006","name":"武当清虚","personality":"儒雅","npc_type":"scholar","pos":Vector2(420,220)},
	{"id":"npc_007","name":"北境猎人","personality":"豪爽","npc_type":"warrior","pos":Vector2(-900,-500)},
	{"id":"npc_009","name":"南山隐士","personality":"慈悲","npc_type":"elder","pos":Vector2(-300,800)},
	{"id":"npc_010","name":"东海渔夫","personality":"豪爽","npc_type":"elder","pos":Vector2(1200,-300)},
	{"id":"npc_011","name":"西域刀客","personality":"阴沉","npc_type":"warrior","pos":Vector2(-1200,100)},
	{"id":"npc_012","name":"雪山道姑","personality":"阴沉","npc_type":"mysterious","pos":Vector2(600,-800)},
]

# 青石城NPC（非门派：商人/手工业者/衙役等）：pos由 world_generator.city_info 建筑锚点解析
# legs=[state, ref, start_hour, end_hour, off]  ref=建筑key/gate:n·s·e·w/plaza  off=门格偏移(格)
# 每人固定作息与岗位（不随机、不扎堆）；21-6及未覆盖时段自动回家睡觉
var city_npc_configs = [
	{"id":"npc_c01","name":"铁三娘","personality":"豪爽","npc_type":"matron_f",
	 "home":["tavern",Vector2(3,1)],
	 "legs":[["work","tavern",7,22,Vector2(0,1)]]},   # 酒楼老板娘：卯时开门营业至亥时
	{"id":"npc_c02","name":"小翠","personality":"活泼","npc_type":"tavern_f",
	 "home":["tavern",Vector2(3,0)],
	 "legs":[["work","tavern",8,14,Vector2(1,1)],["leisure","well",14,16,Vector2(1,0)],["work","tavern",16,21,Vector2(0,1)]]},   # 跑堂：午后去井边取水
	{"id":"npc_c03","name":"白芷","personality":"慈悲","npc_type":"herbalist_f",
	 "home":["apothecary",Vector2(2,1)],
	 "legs":[["work","apothecary",8,18,Vector2(0,1)],["leisure","plaza",18,20,Vector2(1,1)]]},   # 药坊大夫：酉时后广场散步
	{"id":"npc_c04","name":"铁牛","personality":"刚正","npc_type":"warrior",
	 "home":["smithy",Vector2(2,1)],
	 "legs":[["work","smithy",7,18,Vector2(0,1)],["leisure","tavern",18,21,Vector2(-1,1)]]},   # 铁匠：收工后酒楼喝酒
	{"id":"npc_c05","name":"云娘","personality":"儒雅","npc_type":"seamstress_f",
	 "home":["cloth",Vector2(2,1)],
	 "legs":[["work","cloth",8,18,Vector2(0,1)],["leisure","plaza",18,20,Vector2(2,2)]]},   # 布庄老板娘
	{"id":"npc_c06","name":"赵捕头","personality":"刚正","npc_type":"guard",
	 "home":["yamen",Vector2(2,1)],
	 "legs":[["wander","gate:n",6,10,Vector2(1,0)],["wander","plaza",10,14,Vector2(0,0)],["wander","gate:e",14,18,Vector2(-1,0)],["wander","gate:s",18,22,Vector2(0,-1)]]},   # 捕头：四门轮巡
	{"id":"npc_c07","name":"秦师爷","personality":"儒雅","npc_type":"scholar",
	 "home":["yamen",Vector2(3,1)],
	 "legs":[["work","yamen",8,18,Vector2(0,1)],["leisure","tavern",18,20,Vector2(0,1)]]},   # 府衙师爷
	{"id":"npc_c08","name":"王婆婆","personality":"慈悲","npc_type":"matron_f",
	 "home":["house_w",Vector2(1,1)],
	 "legs":[["work","stall_w1",8,19,Vector2(0,1)],["leisure","plaza",19,21,Vector2(0,2)]]},   # 茶贩：西市摊位
	{"id":"npc_c09","name":"小七","personality":"市侩","npc_type":"mysterious",
	 "home":["gate:s",Vector2(2,-2)],
	 "legs":[["idle","gate:s",7,21,Vector2(1,-1)]]},   # 乞丐：日日在南门内侧落脚
	{"id":"npc_c10","name":"更夫老周","personality":"阴沉","npc_type":"elder",
	 "home":["house_w",Vector2(2,1)],
	 "legs":[["wander","plaza",18,24,Vector2(0,0)],["wander","gate:n",0,6,Vector2(0,0)]]},   # 更夫：夜巡白宿
	{"id":"npc_c11","name":"江南沈万","personality":"精明","npc_type":"merchant",
	 "home":["house_ne",Vector2(1,1)],
	 "legs":[["work","stall_e1",8,12,Vector2(0,1)],["leisure","tavern",12,14,Vector2(-1,1)],["work","stall_e1",14,18,Vector2(0,1)],["leisure","tavern",18,21,Vector2(0,1)]]},   # 大商人：东市摆摊，午晚酒楼应酬
]

func _ready():
	y_sort_enabled = true   # Phase G4：NPC并入World递归Y-sort
	_spawn_npcs()
	_spawn_city_npcs()
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
		npc.npc_data = _create_npc_data(cfg, pos, pos + Vector2(randi_range(-80, 80), randi_range(-50, 50)), [])
		add_child(npc)
		npc_list.append(npc)

func _spawn_city_npcs():
	"""青石城NPC：从world_generator.city_info解析建筑/城门/广场锚点，
	按各自日程腿生成固定作息——商人守摊、大夫坐堂、捕头巡城、乞丐守门、更夫夜行"""
	var wg = get_node_or_null("../WorldGenerator")
	if wg == null or not wg.has_method("get_city_info"):
		print("[NPCSpawner] WorldGenerator缺失，跳过城内NPC")
		return
	var info: Dictionary = wg.get_city_info()
	if info.is_empty():
		print("[NPCSpawner] 城池未生成，跳过城内NPC")
		return
	var blds: Dictionary = info.get("buildings", {})
	var gates: Dictionary = info.get("gate_px", {})
	var center_px: Vector2 = info.get("center_px", Vector2.ZERO)
	for cfg in city_npc_configs:
		var home_ref: Array = cfg["home"]
		var home_pos: Vector2 = _resolve_ref(home_ref[0], home_ref[1], blds, gates, center_px)
		var legs: Array = []
		var work_pos: Vector2 = home_pos
		for L in cfg.get("legs", []):
			var p: Vector2 = _resolve_ref(str(L[1]), L[4], blds, gates, center_px)
			if legs.is_empty():
				work_pos = p
			legs.append({"start": int(L[2]), "end": int(L[3]), "state": str(L[0]), "pos": p})
		# 出生点可达性兜底（门前格理论必可达，防御性搬迁）
		var spawn: Vector2 = work_pos
		if wg.has_method("is_world_pos_reachable") and not wg.is_world_pos_reachable(spawn):
			spawn = wg.find_nearest_reachable(spawn)
		var npc = NPC_SCENE.instantiate()
		npc.global_position = spawn
		npc.name = cfg["name"]
		npc.npc_type = cfg.get("npc_type", "warrior")
		npc.npc_data = _create_npc_data(cfg, home_pos, work_pos, legs)
		add_child(npc)
		npc_list.append(npc)
	print("[NPCSpawner] 城内NPC生成: " + str(city_npc_configs.size()) + " 人（青石城）")

func _resolve_ref(ref: String, off: Vector2, blds: Dictionary, gates: Dictionary, center_px: Vector2) -> Vector2:
	"""日程锚点解析：建筑key→门前格，gate:x→城门口，plaza→广场中心；off为格偏移"""
	var base := center_px
	if blds.has(ref):
		base = blds[ref]["door_px"]
	elif gates.has(ref):
		base = gates[ref]
	elif ref.begins_with("gate:"):
		base = gates.get(ref.substr(5), center_px)
	return base + off * 16.0

func _create_npc_data(cfg: Dictionary, home_pos: Vector2, work_pos: Vector2, schedule: Array) -> NPCData:
	var nd = NPCData.new()
	nd.npc_id = cfg["id"]
	nd.npc_name = cfg["name"]
	nd.personality = cfg["personality"]
	var all_likes = ["茶","酒","剑","书","花","棋","武学","美食","金钱","山水"]
	nd.likes = [all_likes[hash(cfg["id"]) % all_likes.size()]]
	nd.dislikes = [all_likes[(hash(cfg["id"]) + 3) % all_likes.size()]]
	nd.home_position = home_pos
	nd.work_position = work_pos
	nd.custom_schedule = schedule
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
	avatar_bg.name = "AvatarBg"
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
		else:
			# 中性好感也给寒暄反馈（此前静默无任何可见表现）
			var small_talk = [
				"这位少侠面生得很，初到本地？",
				"近日江湖不太平，出行还望小心。",
				"听口音是外地人，途中可还顺遂？"
			]
			DialogManager.show_dialog(nd.npc_name, [small_talk[randi() % small_talk.size()]])

func _handle_gift():
	if current_target:
		var nd = current_target.npc_data
		print("[Interact] 向" + nd.npc_name + "送礼")
		GameManager.modify_relation(nd.npc_name, "玩家", 10.0, "neutral")
		# 送礼可见反馈（此前静默只改数值）
		DialogManager.show_dialog(nd.npc_name, [nd.npc_name + "收下了你的心意，神色缓和了不少。（好感+10）"])

func _handle_spar():
	if current_target:
		var nd = current_target.npc_data
		print("[Interact] 与" + nd.npc_name + "切磋")
		# 真实切磋：NPC按职业定基础战力，玩家内力加成+随机，胜负各有得失
		# ⚠️ npc_type在NPC节点上，NPCData没有该字段
		var npc_type: String = "warrior"
		if "npc_type" in current_target:
			npc_type = current_target.npc_type
		var npc_power: int = {"warrior": 14, "guard": 14, "mysterious": 13, "elder": 11, "scholar": 9,
			"merchant": 8, "tavern_f": 7, "matron_f": 7, "herbalist_f": 7, "peasant_f": 6, "seamstress_f": 6}.get(npc_type, 10)
		var my_power: int = 8 + int(GameManager.qi / 20.0) + randi() % 6   # 基础8+内力加成(0~5)+随机0~5
		var lines: Array = [nd.npc_name + "抱拳还礼：「点到为止，请！」两人就地拆起招来。"]
		if my_power >= npc_power:
			GameManager.reputation += 2.0
			GameManager.emit_event("切磋", "你与" + nd.npc_name + "切磋小胜，声望+2", 2)
			lines.append("你招式连贯，一记巧劲卸开对方兵刃占得上风。" + nd.npc_name + "抱拳认输：「佩服。」声望+2")
		else:
			GameManager.health = maxf(GameManager.health - 6.0, 1.0)
			GameManager.emit_event("切磋", "你与" + nd.npc_name + "切磋落败，受伤-6生命", 2)
			lines.append(nd.npc_name + "招式精妙，你渐感不支，收势认负。虽是切磋仍震得手臂发麻，生命-6")
		# 拳脚无情，武人难免介意（保留原好感设定）
		GameManager.modify_relation(nd.npc_name, "玩家", -5.0, "neutral")
		DialogManager.show_dialog(nd.npc_name, lines)

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
	# 填充NPC头像（取idle_down首帧）——Avatar在AvatarBg之下，须用全路径（曾因只查直接子节点永远为null）
	var avatar = panel.get_node_or_null("AvatarBg/Avatar")
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
