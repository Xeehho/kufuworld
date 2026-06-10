class_name ComboTree
extends Resource

@export var routes: Array[ComboRoute] = []

func get_next_skills(from_combo_tag: String) -> Array[String]:
	var result: Array[String] = []
	for route in routes:
		if route.from_tag == from_combo_tag:
			result.append(route.next_skill)
	return result
