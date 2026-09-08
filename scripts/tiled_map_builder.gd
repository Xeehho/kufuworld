@tool
extends Node2D
## Tiled .tmx 直接导入器（2026-09-08）——把用户手拼的 Tiled 地图逐 tile 复刻进 Godot
## 纪律：零修改零重拼——每个 tile（含翻转位）按 tmx 原样铺，tile 贴图直接引用源图集 16px 网格。
## 用法：场景根 Node2D 挂本脚本 + 设 tmx_path，编辑器打开场景或运行时 _ready 自动构建。
## 产物：每个 tmx 图层一个 TileMapLayer 子节点（同名）；纯视觉，无碰撞无业务逻辑。

@export var tmx_path := "res://docs/参考/tiled_work/Outer_city_wall.tmx"

var _tex_cache := {}   # 图集 res 路径 -> ImageTexture

func _ready():
	_build()

func _build():
	for c in get_children():
		if c is TileMapLayer:
			c.queue_free()
	var tmx_dir := tmx_path.get_base_dir()
	var parser := XMLParser.new()
	if parser.open(tmx_path) != OK:
		push_error("[TiledImport] 打不开 tmx: " + tmx_path)
		return
	var W := 0
	var H := 0
	var TS := 16
	# firstgid 有序表 -> {image_res, columns, tilecount}；倒序查找 GID
	var ts_firstgids: Array = []
	var ts_infos := {}
	var layer_name := ""
	var layer_w := 0
	var layer_h := 0
	var in_layer_data := false
	var data_buf := ""
	var layers: Array = []   # [{name, w, h, gids: PackedInt32Array}]
	while parser.read() != ERR_FILE_EOF:
		var t := parser.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var nname := parser.get_node_name()
			if nname == "map":
				W = int(parser.get_named_attribute_value("width"))
				H = int(parser.get_named_attribute_value("height"))
				TS = int(parser.get_named_attribute_value("tilewidth"))
			elif nname == "tileset":
				var fg := int(parser.get_named_attribute_value("firstgid"))
				var tsx_rel := String(parser.get_named_attribute_value("source"))
				var info := _parse_tsx(_join_res(tmx_dir, tsx_rel))
				if info.is_empty():
					push_error("[TiledImport] tsx 解析失败: " + tsx_rel)
					return
				ts_firstgids.append(fg)
				ts_infos[fg] = info
			elif nname == "layer":
				layer_name = parser.get_named_attribute_value("name")
				layer_w = int(parser.get_named_attribute_value("width"))
				layer_h = int(parser.get_named_attribute_value("height"))
			elif nname == "data":
				in_layer_data = true
				data_buf = ""
		elif t == XMLParser.NODE_TEXT and in_layer_data:
			# 长文本会被分多个 TEXT 节点返回，必须全部拼接
			data_buf += parser.get_node_data()
		elif t == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "data":
			in_layer_data = false
			var b64: String = data_buf.strip_edges()
			b64 = b64.replace("\n", "").replace("\r", "").replace("\t", "").replace(" ", "")
			var raw := Marshalls.base64_to_raw(b64)
			# 坑：Godot CompressionMode 命名反直觉——Tiled 的 zlib 流(78xx头)用 DEFLATE(1) 才解得开
			var gids := raw.decompress(layer_w * layer_h * 4, 1)
			if gids.size() < layer_w * layer_h * 4:
				push_error("[TiledImport] 图层%s解压尺寸=%d≠%d" % [layer_name, gids.size(), layer_w * layer_h * 4])
				return
			var arr := PackedInt32Array()
			arr.resize(layer_w * layer_h)
			for i in range(layer_w * layer_h):
				arr[i] = gids.decode_s32(i * 4) & 0xFFFFFFFF   # 转 unsigned 保翻转位
			layers.append({"name": layer_name, "w": layer_w, "h": layer_h, "gids": arr})
	ts_firstgids.sort()
	# 用到的图集 -> TileSetAtlasSource（source_id = firstgid，天然全局唯一）
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TS, TS)
	tileset.tile_shape = TileSet.TILE_SHAPE_SQUARE
	var used_sources := {}
	for L in layers:
		for gid in L["gids"]:
			if gid == 0:
				continue
			var base_gid := int(gid) & 0x1FFFFFFF   # 去三个翻转标志位（tmx GID 低 29 位有效）
			var fg := _find_firstgid(ts_firstgids, base_gid)
			if fg < 0:
				continue
			if used_sources.has(fg):
				continue
			var info: Dictionary = ts_infos[fg]
			var tex := _load_tex(String(info["image"]))
			if tex == null:
				continue
			var src := TileSetAtlasSource.new()
			src.texture = tex
			src.texture_region_size = Vector2i(TS, TS)
			var cols: int = info["columns"]
			var cnt: int = info["tilecount"]
			for idx in range(cnt):
				src.create_tile(Vector2i(idx % cols, idx / cols))
			tileset.add_source(src, fg)
			used_sources[fg] = true
	# 每图层一个 TileMapLayer（按 tmx 顺序 add_child = 渲染顺序）
	for L in layers:
		var lm := TileMapLayer.new()
		lm.name = String(L["name"])
		lm.tile_set = tileset
		add_child(lm)
		var gids: PackedInt32Array = L["gids"]
		var lw: int = L["w"]
		for i in range(gids.size()):
			var gid := gids[i]
			if gid == 0:
				continue
			var fh := bool(gid & 0x80000000)
			var fv := bool(gid & 0x40000000)
			var fd := bool(gid & 0x20000000)
			var base_gid := int(gid) & 0x1FFFFFFF
			var fg := _find_firstgid(ts_firstgids, base_gid)
			if fg < 0 or not used_sources.has(fg):
				continue
			var info: Dictionary = ts_infos[fg]
			var idx := base_gid - fg
			var coords := Vector2i(idx % int(info["columns"]), idx / int(info["columns"]))
			# Tiled 翻转顺序 D→H→V 与 Godot alternative（TRANSPOSE→FLIP_H→FLIP_V）一致，直接位映射
			var alt := 0
			if fh:
				alt |= TileSetAtlasSource.TRANSFORM_FLIP_H
			if fv:
				alt |= TileSetAtlasSource.TRANSFORM_FLIP_V
			if fd:
				alt |= TileSetAtlasSource.TRANSFORM_TRANSPOSE
			lm.set_cell(Vector2i(i % lw, i / lw), fg, coords, alt)
	print("[TiledImport] %s → %d 图层 × %dx%d 格（%d 个源图集）" % [tmx_path.get_file(), layers.size(), W, H, used_sources.size()])

# ---- tsx 解析：返回 {image: res路径, columns, tilecount}（单次遍历：tileset 属性在前、image 在后）----
func _parse_tsx(tsx_res: String) -> Dictionary:
	var p := XMLParser.new()
	if p.open(tsx_res) != OK:
		return {}
	var out := {}
	while p.read() != ERR_FILE_EOF:
		if p.get_node_type() == XMLParser.NODE_ELEMENT:
			if p.get_node_name() == "tileset":
				out["columns"] = int(p.get_named_attribute_value("columns"))
				out["tilecount"] = int(p.get_named_attribute_value("tilecount"))
			elif p.get_node_name() == "image":
				out["image"] = _join_res(tsx_res.get_base_dir(), p.get_named_attribute_value("source"))
				break
	return out

# ---- res:// 相对路径归一（处理 ../）----
func _join_res(base_dir: String, rel: String) -> String:
	var parts := (base_dir + "/" + rel).split("/")
	var stack: Array = []
	for i in range(parts.size()):
		var s := String(parts[i])
		if i == 0:
			continue   # "res:" 协议头
		if s == "" or s == ".":
			continue
		if s == "..":
			if stack.size() > 0:
				stack.pop_back()
			continue
		stack.append(s)
	var path := "res://"
	for i in range(stack.size()):
		path += String(stack[i])
		if i < stack.size() - 1:
			path += "/"
	return path

func _find_firstgid(sorted_gids: Array, gid: int) -> int:
	var lo := -1
	for fg in sorted_gids:
		if fg <= gid:
			lo = int(fg)
		else:
			break
	return lo

# ---- 源图集纹理：downloaded_assets 无 import 数据，走绝对路径 Image 解码 + 内存缓存 ----
func _load_tex(res_path: String) -> ImageTexture:
	if _tex_cache.has(res_path):
		return _tex_cache[res_path]
	var abs_p := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(res_path) and not FileAccess.file_exists(abs_p):
		push_error("[TiledImport] 图集缺失: " + res_path)
		return null
	var img := Image.load_from_file(abs_p)
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[res_path] = tex
	return tex
