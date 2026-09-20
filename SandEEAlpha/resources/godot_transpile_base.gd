extends Node

func python_like_str(object: Variant, context = null) -> String:
	match typeof(object):
		TYPE_NIL:
			return "None"
		TYPE_BOOL:
			if object:
				return "True"
			else:
				return "False"
		TYPE_STRING:
			if context:
				return "'" + object + "'"
			else:
				return object
		TYPE_DICTIONARY:
			var dict: Dictionary = object
			var items: PackedStringArray
			for keys in dict:
				items.append(python_like_str(keys, typeof(object)) + ": " + python_like_str(dict[keys], typeof(object)))
			return "{" + ", ".join(items) + "}"
		TYPE_ARRAY:
			var strings: PackedStringArray = []
			for obj in object:
				strings.append(python_like_str(obj, typeof(object)))
			return "[" + ", ".join(strings) + "]"
		_:
			return str(object)

func godot_print(sep, end, ...objects: Array):
	sep = sep if sep else " "
	end = end if end else ""
	var strings: PackedStringArray = []
	for object in objects:
		strings.append(python_like_str(object))
	var result = sep.join(strings) + end
	get_parent().signal_print.emit(result)
	
func create(object: String):
	get_parent().signal_create.emit(object)
	
