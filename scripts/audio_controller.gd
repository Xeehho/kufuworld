extends Node

# Phase D 音效/BGM占位控制器：WAV由tools/make_phase_d_audio.py程序合成
# 运行时经AudioStreamWAV.load_from_file直读（新文件无import数据，禁用load res://）
# 用法: get_tree().get_first_node_in_group("audio_controller").play_sfx("hit")

const SFX_DIR := "res://audio/sfx/"
const BGM_PATH := "res://audio/bgm/jianghu_loop.wav"
const SFX_NAMES := ["swing", "hit", "hurt", "mob_die", "player_die", "till",
	"water", "plant", "harvest", "craft_ok", "craft_fail", "ui"]
const SFX_VOLUME := -6.0
const BGM_VOLUME := -16.0
const POOL_SIZE := 6

var _sfx: Dictionary = {}
var _pool: Array = []
var _pool_i: int = 0
var bgm_player: AudioStreamPlayer = null
var last_played: String = ""
var history: Array = []   # 最近播放记录（探针断言用）

# 声音设置（暂停菜单设置区开关）：背景音乐默认关闭（用户要求）
var sfx_enabled := true
var bgm_enabled := false

func _ready():
	add_to_group("audio_controller")
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.volume_db = SFX_VOLUME
		add_child(p)
		_pool.append(p)
	for n in SFX_NAMES:
		var path: String = SFX_DIR + str(n) + ".wav"
		if FileAccess.file_exists(path):
			var s := AudioStreamWAV.load_from_file(path)
			if s:
				_sfx[n] = s
	bgm_player = AudioStreamPlayer.new()
	bgm_player.volume_db = BGM_VOLUME
	add_child(bgm_player)
	if FileAccess.file_exists(BGM_PATH):
		var b := AudioStreamWAV.load_from_file(BGM_PATH)
		if b:
			bgm_player.stream = b
			bgm_player.finished.connect(bgm_player.play)   # finished重播实现无缝循环
			if bgm_enabled:
				bgm_player.play()
	print("[Audio] ready sfx=%d/%d bgm=%s" % [_sfx.size(), SFX_NAMES.size(), str(bgm_player.stream != null)])

func set_sfx_enabled(v: bool):
	sfx_enabled = v

func set_bgm_enabled(v: bool):
	bgm_enabled = v
	if bgm_player == null:
		return
	if v:
		if not bgm_player.playing and bgm_player.stream != null:
			bgm_player.play()
	elif bgm_player.playing:
		bgm_player.stop()

func play_sfx(sfx_name: String, volume_db: float = SFX_VOLUME, pitch: float = 1.0) -> bool:
	if not sfx_enabled:
		return false
	if not _sfx.has(sfx_name):
		return false
	var p: AudioStreamPlayer = _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = _sfx[sfx_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
	last_played = sfx_name
	history.append(sfx_name)
	if history.size() > 32:
		history.pop_front()
	return true
