extends Control
## 全局暂停菜单：ESC 在无任何面板打开时呼出；暂停时世界全部冻结
## （process_mode=ALWAYS 保证暂停中菜单自身可响应）

var _panel: PanelContainer
var _sfx_check: CheckButton
var _bgm_check: CheckButton

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()

func _build_ui():
	_panel = PanelContainer.new()
	UITheme.center_panel(_panel, 380, 330)
	add_child(_panel)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_panel.add_child(vb)
	var title = Label.new()
	title.text = "—  暂  停  —"
	UITheme.style_title(title, 30)
	vb.add_child(title)
	var tip = Label.new()
	tip.text = "江湖暂歇，风雪也停了脚步"
	UITheme.style_label(tip, 15, UITheme.TEXT_DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tip)
	var sp = Control.new()
	sp.custom_minimum_size = Vector2(0, 4)
	vb.add_child(sp)
	# ---- 设置区：声音开关 ----
	var set_title = Label.new()
	set_title.text = "设 置"
	UITheme.style_label(set_title, 16, UITheme.GOLD_DIM)
	set_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(set_title)
	_sfx_check = _build_check_row(vb, "音效")
	_bgm_check = _build_check_row(vb, "背景音乐")
	var sp2 = Control.new()
	sp2.custom_minimum_size = Vector2(0, 4)
	vb.add_child(sp2)
	var btn = Button.new()
	btn.text = "继续游戏 (ESC)"
	UITheme.style_button(btn)
	btn.custom_minimum_size = Vector2(200, 44)
	btn.pressed.connect(close_pause)
	var wrap = CenterContainer.new()
	wrap.add_child(btn)
	vb.add_child(wrap)
	# AudioController创建晚于本HUD（Main初始化顺序），延迟同步开关初值
	call_deferred("_sync_audio_checks")

func _build_check_row(parent: Container, label_text: String) -> CheckButton:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl = Label.new()
	lbl.text = label_text
	UITheme.style_label(lbl, 16, UITheme.TEXT_MAIN)
	row.add_child(lbl)
	var chk = CheckButton.new()
	chk.toggled.connect(_on_check_toggled.bind(label_text))
	row.add_child(chk)
	parent.add_child(row)
	return chk

func _sync_audio_checks():
	var ac = get_tree().get_first_node_in_group("audio_controller")
	if ac == null:
		return
	_sfx_check.set_pressed_no_signal(ac.sfx_enabled)
	_bgm_check.set_pressed_no_signal(ac.bgm_enabled)

func _on_check_toggled(pressed: bool, label_text: String):
	var ac = get_tree().get_first_node_in_group("audio_controller")
	if ac == null:
		return
	if label_text == "音效":
		ac.set_sfx_enabled(pressed)
	elif label_text == "背景音乐":
		ac.set_bgm_enabled(pressed)

func _unhandled_input(event):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_ESCAPE and event.physical_keycode != KEY_ESCAPE:
		return
	if get_tree().paused:
		close_pause()
		get_viewport().set_input_as_handled()
	elif not _any_panel_open():
		open_pause()
		get_viewport().set_input_as_handled()

func open_pause():
	if visible:
		return
	get_tree().paused = true
	visible = true
	_panel.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.15)

func close_pause():
	if not visible:
		return
	get_tree().paused = false
	visible = false

func is_paused() -> bool:
	return visible

func _any_panel_open() -> bool:
	# 各面板先消费ESC；此处兜底判断"确无面板"才允许暂停（防关面板瞬间误开暂停）
	var ui = get_node_or_null(".")
	var root = get_node_or_null("/root/Main/World/UI")
	if root == null:
		return false
	if DialogManager.is_dialog_open():
		return true
	var shop = root.get_node_or_null("ShopHUD")
	if shop and shop.get("is_open"):
		return true
	var qm = root.get_node_or_null("QuickMenu")
	if qm and qm.has_method("is_panel_open") and qm.is_panel_open():
		return true
	var qlog = root.get_node_or_null("QuestLogHUD")
	if qlog and qlog.get("expanded"):
		return true
	var cpanel = root.get_node_or_null("CharacterPanel")
	if cpanel and cpanel.visible:
		return true
	var mmap = root.get_node_or_null("MinimapHUD")
	if mmap and mmap.get("_opened"):
		return true
	var death = root.get_node_or_null("DeathHUD")
	if death and death.visible:
		return true
	var player = get_node_or_null("/root/Main/World/Player")
	if player and player.get("state") == player.State.BUILD:
		return true
	return false
