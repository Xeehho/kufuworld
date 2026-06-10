extends Node

var tick_timer: float = 0.0
const TICK_INTERVAL = 10.0
const POWER_CHANGE_PER_TICK = 2.0
const ANNEXATION_THRESHOLD = 15.0

func _process(delta):
	tick_timer += delta
	if tick_timer < TICK_INTERVAL:
		return
	tick_timer = 0.0
	if GameManager.clans.is_empty():
		return
	_tick_economy()
	_tick_diplomacy()
	_tick_war()

func _tick_economy():
	for c in GameManager.clans:
		c.gold += c.member_count * 5
		c.gold -= 100
		c.gold = max(c.gold, 0)
		if c.gold < 50:
			c.power -= 1
			c.member_count = max(c.member_count - 1, 5)

func _tick_diplomacy():
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	for c in GameManager.clans:
		if rng.randf() < 0.05:
			var others: Array = []
			for o in GameManager.clans:
				if o != c:
					others.append(o)
			if others.is_empty():
				continue
			var target = others[rng.randi() % others.size()]
			if c.stance == target.stance:
				if not c.allies.has(target.clan_name):
					GameManager.set_diplomacy(c.clan_name, target.clan_name, "ally")
			else:
				if not c.enemies.has(target.clan_name):
					GameManager.set_diplomacy(c.clan_name, target.clan_name, "enemy")

func _tick_war():
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	for c in GameManager.clans:
		for e in c.enemies:
			var enemy = GameManager.get_clan(e)
			if enemy == null:
				continue
			if rng.randf() < 0.15:
				var ally_power: float = 0.0
				for a in c.allies:
					var ally = GameManager.get_clan(a)
					if ally:
						ally_power += ally.power
				var c_power = c.power + ally_power * 0.3
				var e_ally_power: float = 0.0
				for a in enemy.allies:
					var ally = GameManager.get_clan(a)
					if ally:
						e_ally_power += ally.power
				var e_power = enemy.power + e_ally_power * 0.3

				if c_power > e_power * 1.5:
					enemy.power -= 10
					enemy.member_count = max(enemy.member_count - 2, 1)
					c.power += 3
					if enemy.power < ANNEXATION_THRESHOLD:
						GameManager.handle_clan_annexation(c, enemy)
					GameManager.world_state_changed.emit()
				elif e_power > c_power * 1.5:
					c.power -= 10
					c.member_count = max(c.member_count - 2, 1)
					enemy.power += 3
					if c.power < ANNEXATION_THRESHOLD:
						GameManager.handle_clan_annexation(enemy, c)
					GameManager.world_state_changed.emit()

	for c in GameManager.clans:
		if c.power < ANNEXATION_THRESHOLD:
			GameManager.handle_clan_dissolution(c)
