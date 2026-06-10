extends Control

# 战斗HUD - 显示架势状态、破绽值、连击数

var stance_label: Label
var vuln_bar: ProgressBar
var vuln_label: Label
var combo_label: Label
var counter_label: Label
var stagger_label: Label
var bg_panel: Panel = null

var stagger_flash_timer: float = 0.0

func _ready():
	position = Vector2(10, 172)
	_create_ui()

func _create_ui():
	# 背景面板
	bg_panel = Panel.new()
	bg_panel.size = Vector2(180, 100)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.75)
	style.border_color = Color(0.3, 0.3, 0.4, 0.5)
	style.border_width_bottom = 1
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_right = 1
	bg_panel.add_theme_stylebox_override("panel", style)
	add_child(bg_panel)

	# 架势标签
	stance_label = Label.new()
	stance_label.name = "StanceLabel"
	stance_label.position = Vector2(10, 8)
	stance_label.add_theme_font_size_override("font_size", 14)
	stance_label.add_theme_color_override("font_color", Color(1, 1, 1))
	add_child(stance_label)
	
	# 破绽值条
	vuln_bar = ProgressBar.new()
	vuln_bar.name = "VulnBar"
	vuln_bar.position = Vector2(10, 30)
	vuln_bar.size = Vector2(120, 12)
	vuln_bar.max_value = 100
	vuln_bar.value = 0
	vuln_bar.show_percentage = false
	var vuln_style = StyleBoxFlat.new()
	vuln_style.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	vuln_bar.add_theme_stylebox_override("background", vuln_style)
	var vuln_fill = StyleBoxFlat.new()
	vuln_fill.bg_color = Color(1, 0.3, 0.3, 0.9)
	vuln_bar.add_theme_stylebox_override("fill", vuln_fill)
	add_child(vuln_bar)
	
	# 破绽值文字
	vuln_label = Label.new()
	vuln_label.name = "VulnLabel"
	vuln_label.position = Vector2(135, 28)
	vuln_label.add_theme_font_size_override("font_size", 10)
	vuln_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	vuln_label.text = "破绽:0"
	add_child(vuln_label)
	
	# 连击数
	combo_label = Label.new()
	combo_label.name = "ComboLabel"
	combo_label.position = Vector2(10, 48)
	combo_label.add_theme_font_size_override("font_size", 12)
	combo_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	combo_label.text = ""
	add_child(combo_label)
	
	# 格挡反击提示
	counter_label = Label.new()
	counter_label.name = "CounterLabel"
	counter_label.position = Vector2(10, 66)
	counter_label.add_theme_font_size_override("font_size", 12)
	counter_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1))
	counter_label.text = ""
	add_child(counter_label)
	
	# 大硬直警告
	stagger_label = Label.new()
	stagger_label.name = "StaggerLabel"
	stagger_label.position = Vector2(50, 82)
	stagger_label.add_theme_font_size_override("font_size", 20)
	stagger_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	stagger_label.text = "破绽!"
	stagger_label.visible = false
	add_child(stagger_label)

func _process(delta):
	var cs = _get_combat_stance()
	if cs == null:
		visible = false
		return
	visible = true
	
	# 架势
	var stance_names = ["中立架势", "攻击架势", "防御架势"]
	var stance_colors = [Color(0.8, 0.8, 0.8), Color(1, 0.4, 0.2), Color(0.3, 0.6, 1)]
	stance_label.text = "架势: " + stance_names[cs.current_stance]
	stance_label.add_theme_color_override("font_color", stance_colors[cs.current_stance])
	
	# 破绽值
	vuln_bar.value = cs.vulnerability
	vuln_label.text = "破绽:" + str(int(cs.vulnerability))
	# 破绽值高时变红
	if cs.vulnerability >= 80:
		vuln_label.add_theme_color_override("font_color", Color(1, 0.1, 0.1))
		var fill = vuln_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill:
			fill.bg_color = Color(1, 0.1, 0.1, 0.9)
	elif cs.vulnerability >= 50:
		vuln_label.add_theme_color_override("font_color", Color(1, 0.6, 0.2))
		var fill = vuln_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill:
			fill.bg_color = Color(1, 0.5, 0.2, 0.9)
	else:
		vuln_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
		var fill = vuln_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill:
			fill.bg_color = Color(1, 0.3, 0.3, 0.9)
	
	# 连击
	if cs.hit_count >= 2:
		combo_label.text = "连击 x" + str(cs.hit_count)
	else:
		combo_label.text = ""
	
	# 格挡反击提示
	if cs.is_in_block_counter:
		counter_label.text = ">> 格挡反击! 按轻攻 <<"
	else:
		counter_label.text = ""
	
	# 大硬直警告
	if cs.is_staggered():
		stagger_label.visible = true
		stagger_flash_timer += delta * 6
		stagger_label.modulate.a = 0.5 + 0.5 * sin(stagger_flash_timer)
	else:
		stagger_label.visible = false
		stagger_flash_timer = 0

func _get_combat_stance():
	var main = get_node_or_null("/root/Main")
	if main == null:
		return null
	return main.get_node_or_null("CombatStance")
