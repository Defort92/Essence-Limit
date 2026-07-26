## Константы для соседнего скрипта логики.
## Значения собраны здесь, чтобы их можно было просматривать и настраивать отдельно.
class_name CharacterCreationConstants
extends RefCounted

## Флавор-тексты рас для инфо-панели — чисто UI, не влияет на геймплей.
const RACE_NAMES := {
	GameManager.Race.HUMAN: "Люди",
	GameManager.Race.BARBARIAN: "Варвары",
	GameManager.Race.ELF: "Эльфы",
	GameManager.Race.DEMON: "Демоны",
	GameManager.Race.ANGEL: "Ангелы",
}

const RACE_ROLES := {
	GameManager.Race.HUMAN: "Универсал",
	GameManager.Race.BARBARIAN: "Ближний бой · Танк",
	GameManager.Race.ELF: "Дальний бой",
	GameManager.Race.DEMON: "Ближний бой · ДПС",
	GameManager.Race.ANGEL: "Дальний бой · Магия",
}

const RACE_DESCRIPTIONS := {
	GameManager.Race.HUMAN: "Универсалы. Только люди способны стать магами и зачаровывать оружие.",
	GameManager.Race.BARBARIAN: "Ближний бой и танкование. Усиление через татуировки шамана — но путь паладина для варваров закрыт.",
	GameManager.Race.ELF: "Дальний бой и связь с духами природы.",
	GameManager.Race.DEMON: "Ближний бой (ДПС), доступен путь жреца. Обряды усиления души дают дополнительный слот эссенции.",
	GameManager.Race.ANGEL: "Дальний бой и магия, сильнейшие жреческие заклинания. Обряды усиления души дают дополнительный слот эссенции.",
}

const RACE_UNIQUES := {
	GameManager.Race.HUMAN: "Только люди могут быть волшебниками и зачаровывать оружие.",
	GameManager.Race.BARBARIAN: "Усиление через татуировки от шамана.",
	GameManager.Race.ELF: "Связь с духами природы.",
	GameManager.Race.DEMON: "Обряды усиления души: на последней ступени открывается дополнительный слот для эссенции.",
	GameManager.Race.ANGEL: "Мощнейшие жреческие заклинания и обряды усиления души — дополнительный слот для эссенции.",
}
