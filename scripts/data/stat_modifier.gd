extends Resource
class_name StatModifier

enum Op { ADD, MULTIPLY }

@export var stat: String = ""
@export var op: Op = Op.ADD
@export var value: float = 0.0
@export var source_id: String = ""
