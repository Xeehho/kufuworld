extends Node

# 主线剧情驱动器 v0.1 —— 试验版：序章「青石镇风波」主1~5
# 设计文档: docs/主线剧情设计.md §四
# 推进约定: GameManager.story_stage = 已完成的主线编号（完成主N后=N，触发主N+1）
# 完成模式(complete_mode):
#   dialog    — 指定 meta 的对话结束即完成
#   kills     — 击杀 kill_prefix 前缀怪物 kill_target 只即完成（含 story 任务计数）
#   item      — 背包 item_watch.id 数量达 item_watch.count 即完成
#   oath      — 监听玩家立下 oath_title 的誓言即完成（配合选项键 create_oath）
# 续写方式：向 nodes 追加节点字典即可（第一幕及之后按 P1 计划补）

const DIALOG_TAIL_DELAY := 1.8      # 对话结束后停顿再进入下一节点
const POLL_INTERVAL := 0.5

var quest_system: Node = null
var oath_system: Node = null
var mob_spawner: Node2D = null
var inventory: Node = null

var nodes: Array = []
var node_index: int = -1            # 当前活跃节点(-1=未开始/已完结)
var story_quest_id: String = ""     # 当前节点挂载的story任务id
var kills_progress: int = 0
var item_target_id: String = ""
var item_needed: int = 0
var waiting_oath_title: String = ""
var reopen_pending_meta: String = ""   # 被外部强关(奇遇置顶等)的对话，待环境清静后重开
var branch_resolved_meta: String = ""  # 当前节点已完成过分支选择的meta（防重播双发奖励）
var _poll_accum: float = 0.0
var _encounter_system: Node = null

func _ready():
	nodes = _build_nodes()
	GameManager.story_stage_changed.connect(_on_story_stage_changed)
	DialogManager.option_chosen.connect(_on_dialog_option_chosen)
	DialogManager.dialog_by_meta_finished.connect(_on_dialog_finished)
	call_deferred("_late_setup")

func _late_setup():
	mob_spawner = get_node_or_null("/root/Main/World/MobSpawner")
	quest_system = get_node_or_null("/root/Main/QuestSystem")
	oath_system = get_node_or_null("/root/Main/OathSystem")
	inventory = get_node_or_null("/root/Main/InventoryManager")
	_encounter_system = get_node_or_null("/root/Main/EncounterSystem")
	if mob_spawner:
		mob_spawner.mob_killed.connect(_on_any_mob_killed)
	if inventory:
		inventory.inventory_changed.connect(_on_inventory_changed)
	_start_when_ready()

func _process(delta):
	# 誓约等待（主5 选"暂不立誓"后的兜底轮询）
	if waiting_oath_title != "" and oath_system != null and node_index >= 0:
		_poll_accum += delta
		if _poll_accum >= POLL_INTERVAL:
			_poll_accum = 0.0
			for o in oath_system.oaths:
				if str(o.get("title", "")) == waiting_oath_title:
					waiting_oath_title = ""
					_complete_node(node_index)
					break
	# 被强关的剧情对话重开：等奇遇面板关闭且对话框空闲；已做过分支选择则不重播
	if reopen_pending_meta != "" and node_index >= 0 and reopen_pending_meta != branch_resolved_meta:
		var enc_active: bool = _encounter_system != null and _encounter_system.active_encounter != null
		if not enc_active and not DialogManager.is_dialog_open():
			var cfg: Dictionary = nodes[node_index]
			DialogManager.show_dialog(str(cfg.get("speaker", "")), cfg.get("lines", []), reopen_pending_meta)
			print("[Story] 剧情对话被打断，已自动恢复")
		reopen_pending_meta = ""

# ---------- 节点数据 ----------

func _build_nodes() -> Array:
	return [
		{
			"id": 1, "title": "醒来", "speaker": "石伯",
			"delay": 6.0, "meta": "story_n1",
			"intro_event": ["主线·醒来", "你在青石镇猎户石伯家中养伤初醒，只记得一枚火焰铜牌", 5],
			"lines": [
				"娃，醒啦？三天三夜高烧不退，你这条命是打水里捞回来的。",
				"你昏迷时手里攥着这块刻火焰纹的旧铜牌……老辈人说这是封印之物的样式，来头不小。",
				"罢了，眼下世道不太平，先学几手安身立命的本事。",
				{"text": "WASD走动；屋后柴堆边有把旧斧头，数字键5掏斧、对准树连挥三下放倒拾柴——空手可打不动树。饿了就按1到4伺候庄稼。", "teach_move": true},
				{"text": "（石伯把铜牌塞回你手里）你打算怎么办？", "options": [
					{"text": "接过铜牌细看",
					 "result": "火焰纹路古朴斑驳，指尖传来一丝若有似无的温热——冥冥中似有什么在这江湖尽头等你。"},
					{"text": "追问自己究竟是谁",
					 "result": "石伯摇头叹气：「想起来再急也没用。先把身子养好，江湖不会跑。」"},
				]},
			],
			"complete_mode": "dialog",
			"on_complete": {"wood": 10},
		},
		{
			"id": 2, "title": "地痞闹市", "speaker": "石伯",
			"delay": 4.0, "meta": "story_n2",
			"intro_event": ["主线·地痞闹市", "镇口几个地痞又在欺压菜贩，围观者敢怒不敢言", 4],
			"camp": {"name": "镇口地痞", "offset": Vector2i(14, -9),
				"members": ["orc_rogue", "orc_warrior"]},
			"quest": {"title": "驱散地痞", "desc": "镇口地痞横行，击退两人立威！",
				"target": 2, "reward_gold": 60, "reward_rep": 10},
			"complete_mode": "kills", "kill_prefix": "orc", "kill_target": 2,
			"on_complete": {"morality": 10, "relation": 20, "relation_to": "石伯"},
		},
		{
			"id": 3, "title": "山贼掠镇", "speaker": "镇长秦川",
			"delay": 4.0, "meta": "story_n3",
			"ensure_thief_camp": true,
			"intro_event": ["主线·山贼掠镇", "西边山贼营屡屡下山劫掠农庄粮草，镇民苦不堪言", 4],
			"lines": [
				"少年侠士请留步！听闻你昨日为民出气，颇有些侠骨。",
				"西边山贼营近来屡屡下山掠我农庄粮草，乡亲们苦不堪言呐——只要能荡平那伙贼人，重重有赏！",
				{"text": "秦川搓着手看向你，眼神里透着市侩的精明", "options": [
					{"text": "爽快应承：除贼义不容辞", "effects": {"morality": 5},
					 "result": "好胆色！老夫等你的好消息！"},
					{"text": "讨价还价：先付定金", "effects": {"gold": 40, "morality": -5},
					 "result": "咳……成！先给四十文定金，事成之后再补上！快去吧！"},
				]},
			],
			"quest": {"title": "荡平山贼营", "desc": "镇长悬赏：清剿西边山贼营（击败3名山贼）",
				"target": 3, "reward_gold": 100, "reward_rep": 20},
			"complete_mode": "kills", "kill_prefix": "orc", "kill_target": 3,
			"on_complete": {"relation": 15, "relation_to": "秦川"},
		},
		{
			"id": 4, "title": "安身之道", "speaker": "石伯",
			"delay": 4.0, "meta": "story_n4",
			"intro_event": ["主线·安身之道", "石伯要把祖传的种田手艺教给你", 3],
			"lines": [
				"打打杀杀不是长久饭辙，跟我学侍弄庄稼——会种地的人走到哪都饿不死。",
				"记好喽：数字键1锄头开垦草地、3撒菜种、2浇水，庄稼熟了用4收成；开垦就在这屋后。",
				{"text": "看你心不在焉的样子", "options": [
					{"text": "虚心求教", "effects": {"morality": 2},
					 "result": "孺子可教。记住喽——地不哄人，你对它用心它就还你口粮。"},
					{"text": "心不在焉地应了一声",
					 "result": "哎，年轻人……罢了，去田里练练就知道了。"},
				]},
			],
			"quest": {"title": "初尝耕耘", "desc": "收获一把亲手种的青菜",
				"target": 1, "reward_gold": 40, "reward_rep": 5},
			"item_watch": {"id": "veggie", "count": 1},
			"complete_mode": "item",
			"on_complete": {"hunger": 30, "give_item": "veggie", "give_count": 3},
		},
		{
			"id": 5, "title": "血月之夜", "speaker": "说书人百晓生",
			"delay": 5.0, "meta": "story_n5",
			"intro_event": ["血月凌空", "今夜月色猩红如血，全镇狗吠不止——老人们说是大凶之兆", 6],
			"lines": [
				"客官听说了吗？今夜月带血晕，南疆白骨祭坛昼夜渗血、蛇虫乱窜哇！",
				"三十年前『血手人屠』厉沧海被七大门派联手封在南疆地底——这血月一动，只怕封印将破！",
				"观客官印堂之间隐隐有火纹之气……老朽掐指一算，此劫与你脱不了干系。入江湖者，当立誓明志！",
				{"text": "百晓生摇着折扇等你开口", "options": [
					{"text": "指月立誓：「行侠仗义」", "create_oath": "行侠仗义",
					 "result": "你指月为证，誓要与这满江湖的不平事做个了断。（誓言进度可在右上·誓约面板查看）"},
					{"text": "暂且记在心里，日后再说",
					 "result": "百晓生眯眼一笑：「后生，愿你早立志向——右上角的立誓面板随时为你敞开。」"},
				]},
			],
			"oath_title": "行侠仗义",
			"complete_mode": "oath",
			"on_complete": {"reputation": 10,
				"event_title": "主线·序章终", 
				"event_body": "石伯与百晓生的目光在你身后交汇——下一步，江湖传闻消息集散之地在召唤……", 
				"event_importance": 6},
		},
	]

# ---------- 流程驱动 ----------

func _start_when_ready():
	await get_tree().create_timer(3.0).timeout
	if GameManager.story_stage == 0:
		start_node(0)
	else:
		print("[Story] story_stage=%d，序章试验段已完成或跳过" % GameManager.story_stage)

func start_node(i: int):
	if i < 0 or i >= nodes.size():
		return
	node_index = i
	kills_progress = 0
	var cfg: Dictionary = nodes[i]
	var ev: Array = cfg.get("intro_event", [])
	if ev.size() >= 2:
		GameManager.emit_event(str(ev[0]), str(ev[1]), int(ev[2]) if ev.size() > 2 else 4)
	if bool(cfg.get("ensure_thief_camp", false)):
		_ensure_thief_camp_ready()
	if cfg.has("camp") and mob_spawner:
		var ccfg: Dictionary = cfg["camp"]
		mob_spawner.spawn_story_camp(str(ccfg["name"]), ccfg["offset"], ccfg["members"])
	match String(cfg.get("complete_mode", "")):
		"item":
			var w: Dictionary = cfg["item_watch"]
			item_target_id = str(w["id"])
			item_needed = int(w["count"])
		"oath":
			waiting_oath_title = String(cfg["oath_title"])
	if cfg.has("quest") and quest_system:
		_attach_quest(cfg)
	print("[Story] 主%d「%s」开始" % [cfg["id"], cfg["title"]])
	var lines: Array = cfg.get("lines", [])
	var t := float(cfg.get("delay", 1.0))
	await get_tree().create_timer(t).timeout
	if node_index != i:
		return   # 理论上不会发生；保险
	if not lines.is_empty():
		DialogManager.show_dialog(String(cfg.get("speaker", "")), lines, String(cfg.get("meta", "")))

func _attach_quest(cfg: Dictionary):
	if not cfg.has("quest") or quest_system == null:
		return
	var qcfg: Dictionary = cfg["quest"]
	var q = quest_system.add_story_quest(
		str(qcfg["title"]), str(qcfg["desc"]), int(qcfg.get("target", 1)),
		int(qcfg.get("reward_gold", 0)), float(qcfg.get("reward_rep", 0)),
		float(qcfg.get("reward_morality", 0)))
	story_quest_id = q.quest_id

func _complete_node(idx: int):
	if idx < 0 or idx >= nodes.size() or node_index != idx:
		return
	var cfg: Dictionary = nodes[idx]
	node_index = -1
	story_quest_id = ""
	waiting_oath_title = ""
	item_target_id = ""
	item_needed = 0
	reopen_pending_meta = ""
	branch_resolved_meta = ""
	# 剧情任务已由 progress 链路自动结算奖励；此处应用节点级额外收益并推进阶段
	GameManager.apply_story_effects(cfg.get("on_complete", {}))
	GameManager.advance_story_stage(int(cfg["id"]))
	print("[Story] 主%d「%s」完成" % [cfg["id"], cfg["title"]])
	var nxt: int = idx + 1
	if nxt < nodes.size():
		start_node(nxt)
	else:
		print("[Story] 序章试验段全部完结 (story_stage=%d)，后续节点待P1续写" % GameManager.story_stage)

# ---------- 完成判定监听 ----------

func _on_dialog_finished(meta: String, user_driven: bool):
	if node_index < 0:
		return
	var cfg: Dictionary = nodes[node_index]
	if String(meta) != String(cfg.get("meta", "")):
		return
	if not user_driven:
		# 被奇遇置顶/面板互斥强关：排队重开（对话从头播放，保护分支不被跳过）
		reopen_pending_meta = String(meta)
		print("[Story] 检测到剧情对话被外部打断: " + str(meta))
		return
	if String(cfg.get("complete_mode", "")) != "dialog":
		return
	var finished_idx: int = node_index
	await get_tree().create_timer(DIALOG_TAIL_DELAY).timeout
	_complete_node(finished_idx)

func _on_any_mob_killed(kind_id: String):
	if node_index < 0 or story_quest_id == "":
		return
	var cfg: Dictionary = nodes[node_index]
	if String(cfg.get("complete_mode", "")) != "kills":
		return
	if not kind_id.begins_with(String(cfg.get("kill_prefix", "~"))):
		return
	kills_progress += 1
	if quest_system:
		quest_system.progress_quest(story_quest_id)   # UI进度与任务结算走统一链路
	if kills_progress >= int(cfg.get("kill_target", 99)):
		_complete_node(node_index)

func _on_inventory_changed():
	if node_index < 0 or item_target_id == "":
		return
	if inventory == null or inventory.get_item_count(item_target_id) < item_needed:
		return
	# 达标：锁定目标防止重复触发
	var done_idx: int = node_index
	item_target_id = ""
	item_needed = 0
	if quest_system and story_quest_id != "":
		quest_system.progress_quest(story_quest_id)
	_complete_node(done_idx)

# 主3 前置校验：山贼营若已被提前清空则立即强制补怪（防卡死）
func _ensure_thief_camp_ready():
	if mob_spawner == null or mob_spawner.camps_runtime.is_empty():
		return
	var c: Dictionary = mob_spawner.camps_runtime[0]
	if int(c["alive"]) <= 0:
		c["respawn_timer"] = 0.0
		mob_spawner._spawn_camp(c)
		print("[Story] 山贼营已空，强制补怪以推进剧情")

func _on_dialog_option_chosen(opt: Dictionary):
	# 分支选项效果：誓言类特判交给 OathSystem，其余数值效果统一入口
	if node_index >= 0:
		branch_resolved_meta = String(nodes[node_index].get("meta", ""))
	if opt.has("create_oath") and oath_system:
		oath_system.create_oath(str(opt["create_oath"]))
	var eff = opt.get("effects", {})
	if eff is Dictionary and not eff.is_empty():
		GameManager.apply_story_effects(eff)

func _on_story_stage_changed(stage: int):
	pass   # 预留：阶段变化广播（结局/UIHook 可连接 story_stage_changed 使用）

# 供舆图标注寻路：当前主线目标营地坐标（kills型节点才有目标）
func get_story_target() -> Dictionary:
	if node_index < 0 or mob_spawner == null:
		return {}
	var cfg: Dictionary = nodes[node_index]
	if String(cfg.get("complete_mode", "")) != "kills":
		return {}
	if cfg.has("camp") and not mob_spawner.story_camps.is_empty():
		return {"pos": mob_spawner.story_camps[-1]["center"], "name": String(cfg["title"])}
	if not mob_spawner.camps_runtime.is_empty():
		return {"pos": mob_spawner.camps_runtime[0]["center"], "name": String(cfg["title"])}
	return {}
