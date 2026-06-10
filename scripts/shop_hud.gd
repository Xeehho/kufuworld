extends Control

# 商店UI - 买卖界面、供求价格显示、物品详情
const ITEM_WEAPON = 0
const ITEM_ARMOR = 1
const ITEM_CONSUMABLE = 2
const ITEM_MATERIAL = 3
const ITEM_MANUAL = 4
const ITEM_ACCESSORY = 5

var shop_panel: Panel
var title_label: Label
var item_list: VBoxContainer
var gold_label: Label
var hint_label: Label
var detail_label: Label
var scroll: ScrollContainer
var close_btn: Button = null
var buy_btn: Button = null
var sell_btn: Button = null
var feedback_label: Label = null
var equipped_label: Label = null
var is_open: bool = false
var selected_index: int = -1
var mode: String = "buy"
var displayed_items: Array = []  # Tracks actual items shown in list
var feedback_timer: float = 0.0

func _ready():
	_create_ui()
	visible = false

func _create_ui():
	shop_panel = Panel.new()
	shop_panel.size = Vector2(520, 500)
	shop_panel.position = Vector2(700, 290)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.1, 0.97)
	style.border_color = Color(0.6, 0.5, 0.3)
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	shop_panel.add_theme_stylebox_override("panel", style)
	add_child(shop_panel)

	# 标题
	title_label = Label.new()
	title_label.name = "Title"
	title_label.position = Vector2(15, 10)
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	add_child(title_label)

	# 金钱
	gold_label = Label.new()
	gold_label.name = "Gold"
	gold_label.position = Vector2(300, 10)
	gold_label.add_theme_font_size_override("font_size", 14)
	gold_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	add_child(gold_label)

	# 关闭按钮
	close_btn = Button.new()
	close_btn.text = "X"
	close_btn.size = Vector2(30, 24)
	close_btn.position = Vector2(480, 6)
	close_btn.pressed.connect(close_shop)
	add_child(close_btn)

	# 买入/卖出切换按钮
	buy_btn = Button.new()
	buy_btn.text = " 买入 "
	buy_btn.size = Vector2(70, 26)
	buy_btn.position = Vector2(15, 34)
	buy_btn.pressed.connect(func(): mode = "buy"; _refresh_display())
	add_child(buy_btn)

	sell_btn = Button.new()
	sell_btn.text = " 卖出 "
	sell_btn.size = Vector2(70, 26)
	sell_btn.position = Vector2(90, 34)
	sell_btn.pressed.connect(func(): mode = "sell"; _refresh_display())
	add_child(sell_btn)

	# 物品列表
	scroll = ScrollContainer.new()
	scroll.position = Vector2(15, 66)
	scroll.size = Vector2(490, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	item_list = VBoxContainer.new()
	item_list.name = "ItemList"
	item_list.add_theme_constant_override("separation", 3)
	scroll.add_child(item_list)

	# 物品详情区域
	var detail_bg = Panel.new()
	detail_bg.position = Vector2(15, 352)
	detail_bg.size = Vector2(490, 70)
	var detail_style = StyleBoxFlat.new()
	detail_style.bg_color = Color(0.04, 0.04, 0.08, 0.9)
	detail_style.border_color = Color(0.3, 0.3, 0.4)
	detail_style.border_width_bottom = 1
	detail_style.border_width_top = 1
	detail_style.border_width_left = 1
	detail_style.border_width_right = 1
	detail_bg.add_theme_stylebox_override("panel", detail_style)
	add_child(detail_bg)

	detail_label = Label.new()
	detail_label.position = Vector2(20, 356)
	detail_label.size = Vector2(480, 62)
	detail_label.add_theme_font_size_override("font_size", 10)
	detail_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	detail_label.text = "选择物品查看详情"
	add_child(detail_label)

	# 装备信息（卖出模式显示）
	equipped_label = Label.new()
	equipped_label.position = Vector2(15, 426)
	equipped_label.size = Vector2(490, 40)
	equipped_label.add_theme_font_size_override("font_size", 10)
	equipped_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1))
	equipped_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	equipped_label.text = ""
	equipped_label.visible = false
	add_child(equipped_label)

	# 交易反馈
	feedback_label = Label.new()
	feedback_label.position = Vector2(15, 470)
	feedback_label.size = Vector2(490, 20)
	feedback_label.add_theme_font_size_override("font_size", 11)
	feedback_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
	feedback_label.text = ""
	add_child(feedback_label)

	# 操作提示
	hint_label = Label.new()
	hint_label.name = "Hint"
	hint_label.position = Vector2(15, 486)
	hint_label.add_theme_font_size_override("font_size", 9)
	hint_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint_label.text = "K=开关 | 1-9=选择 | Tab=切换买/卖 | R=使用/装备"
	add_child(hint_label)

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.is_action_pressed("toggle_shop"):
			toggle_shop()
		elif is_open:
			if event.keycode == KEY_TAB:
				mode = "sell" if mode == "buy" else "buy"
				_refresh_display()
			elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
				var idx = event.keycode - KEY_1
				_handle_select(idx)
			elif event.is_action_pressed("shop_use_equip"):
				_handle_use_equipped()

func _process(delta):
	if feedback_timer > 0:
		feedback_timer -= delta
		if feedback_timer <= 0:
			feedback_label.text = ""

func toggle_shop():
	if is_open:
		close_shop()
	else:
		open_shop()

func open_shop():
	is_open = true
	visible = true
	var shop = _get_shop()
	if shop:
		shop.open_shop()
	_refresh_display()

func close_shop():
	is_open = false
	visible = false
	var shop = _get_shop()
	if shop:
		shop.close_shop()

func _refresh_display():
	var shop = _get_shop()
	if shop == null:
		return

	title_label.text = shop.shop_name
	gold_label.text = "铜钱: " + str(GameManager.gold)

	# 更新买入/卖出按钮样式
	var active_style = StyleBoxFlat.new()
	active_style.bg_color = Color(0.2, 0.15, 0.05, 1.0)
	active_style.border_color = Color(1, 0.85, 0.3)
	active_style.border_width_bottom = 2
	active_style.border_width_top = 2
	active_style.border_width_left = 2
	active_style.border_width_right = 2

	var inactive_style = StyleBoxFlat.new()
	inactive_style.bg_color = Color(0.1, 0.1, 0.12, 0.8)
	inactive_style.border_color = Color(0.3, 0.3, 0.3)
	inactive_style.border_width_bottom = 1
	inactive_style.border_width_top = 1
	inactive_style.border_width_left = 1
	inactive_style.border_width_right = 1

	if mode == "buy":
		buy_btn.add_theme_stylebox_override("normal", active_style)
		sell_btn.add_theme_stylebox_override("normal", inactive_style)
		buy_btn.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		sell_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	else:
		sell_btn.add_theme_stylebox_override("normal", active_style)
		buy_btn.add_theme_stylebox_override("normal", inactive_style)
		sell_btn.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		buy_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

	for child in item_list.get_children():
		child.queue_free()

	displayed_items.clear()
	detail_label.text = "选择物品查看详情"

	if mode == "buy":
		_show_buy_list(shop)
		equipped_label.visible = false
	else:
		_show_sell_list()
		_show_equipped_info()
		equipped_label.visible = true

func _show_buy_list(shop):
	displayed_items.clear()
	var display_idx = 0
	for i in range(shop.shop_items.size()):
		var slot = shop.shop_items[i]
		var item = slot["item"]
		if slot["stock"] <= 0:
			continue

		var price = shop.get_buy_price(item)
		var rarity_badge = _get_rarity_badge(item.rarity)
		var supply_indicator = _get_supply_indicator(item.supply_level)
		var color = _get_rarity_color(item.rarity)

		var lbl = Label.new()
		var key_str = str(display_idx + 1) if display_idx < 9 else "-"
		lbl.text = "[%s] %s %s %s | %d铜 %s | 库存:%d" % [key_str, rarity_badge, item.item_name, item.get_type_name(), price, supply_indicator, slot["stock"]]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", color)
		item_list.add_child(lbl)

		displayed_items.append({"item": item, "shop_index": i, "price": price, "stock": slot["stock"]})
		display_idx += 1

func _show_sell_list():
	var inv = _get_inventory()
	if inv == null:
		return
	displayed_items.clear()
	var idx = 0
	for slot in inv.inventory:
		var item = slot["item"]
		var shop = _get_shop()
		var price = shop.get_sell_price(item) if shop else int(item.base_price * 0.5)
		var rarity_badge = _get_rarity_badge(item.rarity)
		var color = _get_rarity_color(item.rarity)

		var lbl = Label.new()
		var key_str = str(idx + 1) if idx < 9 else "-"
		lbl.text = "[%s] %s %s x%d | 卖%d铜 | %s" % [key_str, rarity_badge, item.item_name, slot["count"], price, item.get_effect_description().left(20)]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", color)
		item_list.add_child(lbl)

		displayed_items.append({"item": item, "inv_index": idx, "price": price, "count": slot["count"]})
		idx += 1

func _show_equipped_info():
	var inv = _get_inventory()
	if inv == null:
		return
	var info = "当前装备: "
	if inv.equipped_weapon:
		info += "武器[%s 攻+%d] " % [inv.equipped_weapon.item_name, int(inv.equipped_weapon.attack_bonus)]
	else:
		info += "武器[无] "
	if inv.equipped_armor:
		info += "防具[%s 防+%d] " % [inv.equipped_armor.item_name, int(inv.equipped_armor.defense_bonus)]
	else:
		info += "防具[无] "
	if inv.equipped_accessory:
		info += "饰品[%s]" % inv.equipped_accessory.item_name
	else:
		info += "饰品[无]"
	equipped_label.text = info

func _handle_select(idx: int):
	if idx < 0 or idx >= displayed_items.size():
		return

	var entry = displayed_items[idx]
	var item = entry["item"]

	# Show detail
	_show_item_detail(item)

	var shop = _get_shop()
	if shop == null:
		return

	if mode == "buy":
		var shop_idx = entry["shop_index"]
		if shop.buy_item(shop_idx):
			_show_feedback("已购买 %s -%d铜" % [item.item_name, entry["price"]])
		else:
			_show_feedback("购买失败! 铜钱不足或库存不足")
	else:
		if shop.sell_item(item.item_id):
			_show_feedback("已卖出 %s +%d铜" % [item.item_name, entry["price"]])
		else:
			_show_feedback("卖出失败!")
	_refresh_display()

func _handle_use_equipped():
	var inv = _get_inventory()
	if inv == null:
		return
	if mode == "sell":
		for slot in inv.inventory:
			var item = slot["item"]
			if item.item_type == ITEM_CONSUMABLE:
				inv.use_item(item.item_id)
				_show_feedback("使用了 %s" % item.item_name)
				_refresh_display()
				return
			elif item.item_type == ITEM_WEAPON or item.item_type == ITEM_ARMOR or item.item_type == ITEM_ACCESSORY:
				inv.equip_item(item.item_id)
				_show_feedback("装备了 %s" % item.item_name)
				_refresh_display()
				return

func _show_item_detail(item):
	var detail = "[%s] %s - %s\n" % [_get_rarity_badge(item.rarity), item.item_name, item.get_rarity_name()]
	detail += item.description + "\n"
	detail += item.get_effect_description()
	if item.supply_level > 0 or item.demand_level > 0:
		detail += "\n供需: 供应%d/需求%d" % [item.supply_level, item.demand_level]
	detail_label.text = detail

func _show_feedback(msg: String):
	feedback_label.text = msg
	feedback_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3) if "已" in msg else Color(1, 0.4, 0.3))
	feedback_timer = 2.5

func _get_rarity_badge(rarity: int) -> String:
	var badges = ["凡", "良", "稀", "史", "传"]
	if rarity >= 0 and rarity < badges.size():
		return "[" + badges[rarity] + "]"
	return "[凡]"

func _get_rarity_color(rarity: int) -> Color:
	var colors = [Color(0.8, 0.8, 0.8), Color(0.3, 1, 0.3), Color(0.3, 0.6, 1), Color(0.8, 0.3, 1), Color(1, 0.8, 0.2)]
	if rarity >= 0 and rarity < colors.size():
		return colors[rarity]
	return Color.WHITE

func _get_supply_indicator(level: int) -> String:
	if level >= 80:
		return "(供>>求)"
	elif level >= 60:
		return "(供>求)"
	elif level >= 40:
		return "(供=求)"
	elif level >= 20:
		return "(供<求)"
	else:
		return "(供<<求)"

func _get_shop():
	var main = get_node_or_null("/root/Main")
	if main:
		return main.get_node_or_null("ShopSystem")
	return null

func _get_inventory():
	var main = get_node_or_null("/root/Main")
	if main:
		return main.get_node_or_null("InventoryManager")
	return null
