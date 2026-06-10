class_name DialogueTree
extends Resource

@export var npc_id: String = ""
@export var entries: Array[DialogueEntry] = []

func get_entry(id_str: String) -> DialogueEntry:
	for e in entries:
		if e.entry_id == id_str:
			return e
	return null
