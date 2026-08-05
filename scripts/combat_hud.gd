extends Control

# 战斗HUD - 仅在战斗触发时动态显示，紧凑美观的浮动条

var stance_label: Label = null
var vuln_bar_bg: ColorRect = null
var vuln_bar_fg: ColorRect = null
var vuln_text: Label = null
var combo_label: Label = null
var counter_label: Label = null
var stagger_label: Label = null

# 动态显隐
var show_timer: float = 0.0
const HIDE_DELAY = 2.5  # 无战斗动作后多久隐藏
var was_in_combat: bool = false
var stagger_flash_timer: float = 0.0

func _ready():
	position = Vector2(185, 10)
	_create_ui()
	visible = false

func _create_ui():
	var bar_w = 170.0
	var bar_h = 38.0

	# 背景面板 - 圆角半透明条
	var bg = Panel.new()
	bg.size = Vector2(bar_w, bar_h)
	bg.add_theme_stylebox_override("panel", UITheme.inset_style())
	add_child(bg)

	# 架势标签（左侧）
	stance_label = Label.new()
	stance_label.position = Vector2(8, 5)
	stance_label.add_theme_font_size_override("font_size", 12)
	stance_label.text = "中立"
	add_child(stance_label)

	# 破绽值条（中间）
	vuln_bar_bg = ColorRect.new()
	vuln_bar_bg.color = Color(0.15, 0.15, 0.18, 0.8)
	vuln_bar_bg.position = Vector2(8, 24)
	vuln_bar_bg.size = Vector2(110, 8)
	add_child(vuln_bar_bg)

	vuln_bar_fg = ColorRect.new()
	vuln_bar_fg.color = Color(1, 0.3, 0.3, 0.9)
	vuln_bar_fg.position = Vector2(8, 24)
	vuln_bar_fg.size = Vector2(0, 8)
	add_child(vuln_bar_fg)

	vuln_text = Label.new()
	vuln_text.position = Vector2(122, 21)
	vuln_text.add_theme_font_size_override("font_size", 9)
	vuln_text.text = "破绽:0"
	vuln_text.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	add_child(vuln_text)

	# 连击数（右侧）
	combo_label = Label.new()
	combo_label.position = Vector2(bar_w - 50, 6)
	combo_label.add_theme_font_size_override("font_size", 11)
	combo_label.add_theme_color_override("font_color", Color(1, 0.85, 0.25))
	combo_label.text = ""
	add_child(combo_label)

	# 格挡反击提示（覆盖在条上）
	counter_label = Label.new()
	counter_label.position = Vector2(30, 7)
	counter_label.add_theme_font_size_override("font_size", 10)
	counter_label.add_theme_color_override("font_color", Color(0.35, 0.75, 1))
	counter_label.text = ""
	add_child(counter_label)

	# 大硬直警告
	stagger_label = Label.new()
	stagger_label.position = Vector2(55, 10)
	stagger_label.add_theme_font_size_override("font_size", 16)
	stagger_label.add_theme_color_override("font_color", Color(1, 0.15, 0.15))
	stagger_label.text = "破绽!"
	stagger_label.visible = false
	add_child(stagger_label)

func _process(delta):
	var cs = _get_combat_stance()
	if cs == null:
		if visible:
			show_timer -= delta
			if show_timer <= 0:
				visible = false
		return

	var in_combat = _is_player_in_combat()

	if in_combat:
		show_timer = HIDE_DELAY
		if not visible:
			visible = true
	elif visible:
		show_timer -= delta
		if show_timer <= 0:
			visible = false
			return

	# 更新战斗数据
	_update_stance(cs)
	_update_vulnerability(cs)
	_update_combo(cs)
	_update_counter(cs)
	_update_stagger(cs, delta)

func _is_player_in_combat() -> bool:
	var player = get_node_or_null("/root/Main/World/Player")
	if player == null:
		return false
	# 检查玩家是否处于战斗状态
	match player.state:
		player.State.ATTACK, player.State.BLOCK, player.State.DODGE, player.State.STAGGER:
			return true
	return false

func _update_stance(cs):
	var stance_names = ["中立", "攻击", "防御"]
	var stance_colors = [Color(0.75, 0.75, 0.75), Color(1, 0.45, 0.2), Color(0.35, 0.65, 1)]
	var idx = clamp(cs.current_stance, 0, 2)
	stance_label.text = stance_names[idx]
	stance_label.add_theme_color_override("font_color", stance_colors[idx])

func _update_vulnerability(cs):
	var v = cs.vulnerability
	var bar_w = 110.0
	vuln_bar_fg.size.x = bar_w * clamp(v / 100.0, 0, 1)
	vuln_text.text = str(int(v))

	if v >= 80:
		vuln_bar_fg.color = Color(1, 0.1, 0.1, 0.95)
		vuln_text.add_theme_color_override("font_color", Color(1, 0.1, 0.1))
	elif v >= 50:
		vuln_bar_fg.color = Color(1, 0.5, 0.15, 0.92)
		vuln_text.add_theme_color_override("font_color", Color(1, 0.6, 0.2))
	else:
		vuln_bar_fg.color = Color(1, 0.3, 0.3, 0.88)
		vuln_text.add_theme_color_override("font_color", Color(1, 0.5, 0.5))

func _update_combo(cs):
	if cs.hit_count >= 2:
		combo_label.text = "x" + str(cs.hit_count)
	else:
		combo_label.text = ""

func _update_counter(cs):
	if cs.is_in_block_counter:
		counter_label.text = ">> 反击 <<"
	else:
		counter_label.text = ""

func _update_stagger(cs, delta):
	if cs.is_staggered():
		stagger_label.visible = true
		stagger_flash_timer += delta * 6
		stagger_label.modulate.a = 0.5 + 0.5 * sin(stagger_flash_timer)
		# 隐藏其他信息突出警告
		stance_label.visible = false
		combo_label.visible = false
		counter_label.visible = false
		vuln_bar_bg.visible = false
		vuln_bar_fg.visible = false
		vuln_text.visible = false
	else:
		stagger_label.visible = false
		stagger_flash_timer = 0
		stance_label.visible = true
		combo_label.visible = true
		counter_label.visible = true
		vuln_bar_bg.visible = true
		vuln_bar_fg.visible = true
		vuln_text.visible = true

func _get_combat_stance():
	var main = get_node_or_null("/root/Main")
	if main == null:
		return null
	return main.get_node_or_null("CombatStance")
