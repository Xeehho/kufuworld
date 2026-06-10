extends Control

# 死亡界面HUD - 显示结局、传承信息

var death_panel: Panel
var outcome_label: Label
var detail_label: Label
var timer_label: Label
var inheritance_label: Label

var show_timer: float = 0.0

func _ready():
	_create_ui()
	visible = false

func _create_ui():
	death_panel = Panel.new()
	death_panel.size = Vector2(400, 220)
	death_panel.position = Vector2(760, 340)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.02, 0.02, 0.95)
	style.border_color = Color(0.8, 0.2, 0.2)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	death_panel.add_theme_stylebox_override("panel", style)
	add_child(death_panel)
	
	outcome_label = Label.new()
	outcome_label.name = "Outcome"
	outcome_label.position = Vector2(20, 15)
	outcome_label.add_theme_font_size_override("font_size", 20)
	outcome_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	outcome_label.text = "气血归零..."
	add_child(outcome_label)
	
	detail_label = Label.new()
	detail_label.name = "Detail"
	detail_label.position = Vector2(20, 50)
	detail_label.add_theme_font_size_override("font_size", 13)
	detail_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.7))
	detail_label.text = ""
	add_child(detail_label)
	
	timer_label = Label.new()
	timer_label.name = "Timer"
	timer_label.position = Vector2(20, 130)
	timer_label.add_theme_font_size_override("font_size", 12)
	timer_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	timer_label.text = ""
	add_child(timer_label)
	
	inheritance_label = Label.new()
	inheritance_label.name = "Inheritance"
	inheritance_label.position = Vector2(20, 160)
	inheritance_label.add_theme_font_size_override("font_size", 11)
	inheritance_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1))
	inheritance_label.text = ""
	add_child(inheritance_label)

func _process(delta):
	var ds = _get_death_system()
	if ds == null:
		visible = false
		return
	
	if ds.is_dead:
		visible = true
		show_timer += delta
		outcome_label.text = "气血归零..."
		outcome_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		
		var outcome_name = ds.get_death_outcome_name()
		detail_label.text = "结局: " + outcome_name
		
		if ds.death_outcome == 0:  # RESCUED
			detail_label.text += "\n侠义在身，路遇贵人相救"
			detail_label.text += "\n损失部分铜钱，恢复部分气血"
		elif ds.death_outcome == 1:  # IMPRISONED
			detail_label.text += "\n恶名远扬，身陷囹圄"
			detail_label.text += "\n损失铜钱和声望，关押30秒"
		elif ds.death_outcome == 2:  # INHERITANCE
			detail_label.text += "\n江湖路远，薪火相传"
			detail_label.text += "\n以传人身份继续，继承部分武学和关系"
			inheritance_label.text = ds.get_inheritance_info()
		
		var remaining = max(ds.respawn_timer, 0)
		timer_label.text = "复活倒计时: " + str(int(remaining) + 1) + "秒"
	elif ds.is_imprisoned():
		visible = true
		outcome_label.text = "囚禁中..."
		outcome_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		detail_label.text = "等待刑满释放..."
		var remaining = max(ds.imprisonment_timer, 0)
		timer_label.text = "剩余: " + str(int(remaining) + 1) + "秒"
		inheritance_label.text = ""
	else:
		visible = false
		show_timer = 0

func _get_death_system():
	var main = get_node_or_null("/root/Main")
	if main:
		return main.get_node_or_null("DeathSystem")
	return null
