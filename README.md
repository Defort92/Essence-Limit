# Essence Limit

2.5D Dark Fantasy RPG на Godot 4 | GDScript

## Godot для backend-разработчика

| Godot | Аналог в backend |
|-------|-----------------|
| Сцена `.tscn` | Объект / структура данных |
| Скрипт `.gd` | Класс / логика |
| Автозагрузка | Синглтон / глобальный сервис |
| Signal | Event / callback |
| Resource `.tres` | Immutable config-object |
| Area3D | Trigger zone / сенсор |
| CharacterBody3D | Entity с физикой |

---

## Текущее состояние проекта

| Система | Файл | Статус |
|---------|------|--------|
| GameManager | `scripts/systems/game_manager.gd` | ✅ расы, статы, золото |
| XPSystem | `scripts/systems/xp_system.gd` | ✅ XP, уровни (кап 100), first-kill |
| EssenceSystem | `scripts/systems/essence_system.gd` | ✅ слоты, установка/удаление |
| DungeonPortal | `scripts/systems/dungeon_portal.gd` | ✅ открытие/закрытие портала |
| InventorySystem | `scripts/systems/inventory_system.gd` | ✅ рюкзак (30 слотов) |
| StashSystem | `scripts/systems/stash_system.gd` | ✅ хранилище (100 слотов) |
| EquipmentManager | `scripts/systems/equipment_manager.gd` | ✅ надевание/снятие снаряжения |
| SaveSystem | `scripts/systems/save_system.gd` | ✅ JSON, 3 слота сохранения |
| PauseManager | `scripts/systems/pause_manager.gd` | ✅ пауза / сигналы |
| AbilityManager | `scripts/systems/ability_manager.gd` | ✅ спавн/удаление способностей эссенций |
| RacialPassiveSystem | `scripts/systems/racial_passive_system.gd` | ✅ расовые пассивки |
| AchievementSystem | `scripts/systems/achievement_system.gd` | ✅ достижения + награды |
| AuraComponent | `scripts/components/aura_component.gd` | ✅ пассивный эффект в радиусе |
| AbilityBase | `scripts/entities/ability_base.gd` | ✅ базовый класс способности |
| BossBase | `scripts/entities/boss_base.gd` | ✅ враг с фазами |
| AchievementData | `scripts/data/achievement_data.gd` | ✅ Resource-класс |
| Player | `scripts/entities/player.gd` | ✅ движение, dodge, HP, статы |
| Enemy | `scripts/entities/enemy.gd` | ✅ AI, модификаторы, лут-сигнал |
| ItemPickup | `scripts/entities/item_pickup.gd` | ✅ автоподбор через Area3D |
| Camera | `scripts/camera/game_camera.gd` | ✅ следит за игроком |
| ItemData | `scripts/data/item_data.gd` | ✅ базовый класс предметов |
| EquipmentData | `scripts/data/equipment_data.gd` | ✅ HEAD/BODY/LEGS/GLOVES/оружие/аксессуар |
| EssenceData | `scripts/data/essence_data.gd` | ✅ Resource-класс |
| ConsumableData | `scripts/data/consumable_data.gd` | ✅ зелья, расходники |
| EnemyData | `scripts/data/enemy_data.gd` | ✅ + LootTable |
| LootTable | `scripts/systems/loot_table.gd` | ✅ весовой дроп |
| main.tscn | `scenes/main.tscn` | ✅ тестовый уровень |
| player.tscn | `scenes/characters/player.tscn` | ✅ капсула-placeholder |

---

## Что нужно сделать в Godot Editor (обязательно перед запуском)

### 1. Зарегистрировать Autoload-синглтоны

**Project → Project Settings → Autoload**, порядок важен:

| Имя | Путь |
|-----|------|
| GameManager | `scripts/systems/game_manager.gd` |
| XPSystem | `scripts/systems/xp_system.gd` |
| EssenceSystem | `scripts/systems/essence_system.gd` |
| DungeonPortal | `scripts/systems/dungeon_portal.gd` |
| InventorySystem | `scripts/systems/inventory_system.gd` |
| StashSystem | `scripts/systems/stash_system.gd` |
| EquipmentManager | `scripts/systems/equipment_manager.gd` |
| AbilityManager | `scripts/systems/ability_manager.gd` |
| RacialPassiveSystem | `scripts/systems/racial_passive_system.gd` |
| AchievementSystem | `scripts/systems/achievement_system.gd` |
| SaveSystem | `scripts/systems/save_system.gd` |
| PauseManager | `scripts/systems/pause_manager.gd` |

### 2. Добавить Input Actions

**Project → Project Settings → Input Map:**

| Action | Клавиша по умолчанию |
|--------|----------------------|
| `move_left` | A |
| `move_right` | D |
| `move_up` | W |
| `move_down` | S |
| `dodge` | Space |
| `attack` | ЛКМ (Mouse Button Left) |
| `block` | ПКМ (Mouse Button Right) |
| `pause` | Escape |
| `ability_1` | Q |
| `ability_2` | E |
| `ability_3` | R |
| `ability_4` | F |
| `consumable_1` | 1 |
| `consumable_2` | 2 |
| `consumable_3` | 3 |
| `consumable_4` | 4 |

---

## Этап 1 — Видимая игра

- [x] **1.1** Убедиться что `main.tscn` запускается — капсула ходит по полу, камера следит
- [x] **1.2** Создать `scenes/ui/hud.tscn` + `scripts/ui/hud.gd` — полоска HP, золото, уровень
- [ ] **1.3** Настроить угол камеры (`offset` в `scripts/camera/game_camera.gd`)
- [ ] **1.4** Создать `scenes/characters/enemy_test.tscn` — враг ходит к игроку, бьёт, умирает
- [ ] **1.5** Мигание красным при получении урона (Tween на материале или модуляции)

---

## Этап 2 — Создание персонажа

- [ ] **2.1** Создать `scenes/ui/character_creation.tscn` — 5 кнопок рас с описанием
- [ ] **2.2** Базовые статы из расы применяются автоматически через `GameManager.get_race_base_stats()`
- [ ] **2.3** Поле ввода имени персонажа → `GameManager.player_name`
- [ ] **2.4** Кнопка "Начать игру" → `SaveSystem.save(0)` → смена сцены на стартовую локацию расы

---

## Этап 3 — Главное меню и пауза

- [ ] **3.1** `scenes/ui/main_menu.tscn` — Новая игра / Загрузить (3 слота через `SaveSystem.get_save_info()`) / Выйти
- [ ] **3.2** `scenes/ui/pause_menu.tscn` — Продолжить / Сохранить / Выйти в меню
  - Узел должен иметь `process_mode = WHEN_PAUSED`
  - Слушать `PauseManager.paused` / `PauseManager.unpaused`

---

## Этап 4 — Человеческий город

- [ ] **4.1** Создать `scenes/world/human_city.tscn` — карта через GridMap (пол, стены, дорога)
- [ ] **4.2** Коллизии для стен — игрок не проходит сквозь здания
- [ ] **4.3** Создать `scripts/world/transition_zone.gd` — Area3D-переходы по углам к локациям рас
- [ ] **4.4** Создать `scripts/world/portal_zone.gd` — зона входа в подземелье (активна если портал открыт)
- [ ] **4.5** NPC-заглушки на месте торговцев и ремесленников

---

## Этап 5 — Боевая система

- [ ] **5.1** Добавить в `scenes/characters/player.tscn` AttackArea (Area3D перед персонажем)
- [ ] **5.2** В `scripts/entities/player.gd`: по ЛКМ — активировать Area3D, нанести урон Enemy в зоне
- [ ] **5.3** Уклонение (Пробел) — рывок + временный i-frame (неуязвимость ~0.3 сек)
- [ ] **5.4** Полоска HP над головой врага (billboard ProgressBar или Label3D)
- [ ] **5.5** Смерть врага: анимация исчезновения, спавн ItemPickup через сигнал `loot_dropped`
- [ ] **5.6** Создать `scenes/ui/death_screen.tscn` — "Вы погибли" + кнопка возврата в город

---

## Этап 6 — Инвентарь и снаряжение (UI)

- [ ] **6.1** `scenes/ui/inventory.tscn` — сетка слотов (клавиша I), данные из `InventorySystem`
- [ ] **6.2** Панель снаряжения: слоты HEAD / BODY / LEGS / GLOVES / WEAPON_MAIN / WEAPON_OFF / ACCESSORY ×3
  - Клик по предмету в рюкзаке → `EquipmentManager.equip(item)`
  - Клик по слоту снаряжения → `EquipmentManager.unequip_slot(slot)`
- [ ] **6.3** `scenes/ui/stash.tscn` — хранилище (доступно только в городе)
  - `StashSystem.deposit()` / `StashSystem.withdraw()`
- [ ] **6.4** `scenes/world/item_pickup.tscn` — сцена для ItemPickup-скрипта с визуалом
- [ ] **6.5** Панель характеристик: вызов `Player.get_total_stat()` по всем статам

---

## Этап 7 — Система эссенций (UI)

- [ ] **7.1** `scenes/ui/essence_panel.tscn` — слоты (кол-во = уровень), данные из `EssenceSystem`
- [ ] **7.2** Установка эссенции: drag & drop из инвентаря в слот → `EssenceSystem.equip(essence)`
- [ ] **7.3** Удаление: только в городе, за золото → `EssenceSystem.remove(index)`
- [ ] **7.4** Создать 3–5 тестовых эссенций как `.tres` в `resources/essences/`

---

## Этап 8 — Торговля и экономика

- [ ] **8.1** `scenes/ui/shop.tscn` — два столбца: товары / инвентарь
- [ ] **8.2** Покупка: `GameManager.spend_gold(buy_price)` + `InventorySystem.add_item()`
- [ ] **8.3** Продажа: `InventorySystem.remove_item()` + `GameManager.add_gold(sell_price)`
- [ ] **8.4** NPC-ремесленник: удаление эссенции за плату через `EssenceSystem.remove()`

---

## Этап 9 — Подземелье: первый этаж

- [ ] **9.1** Создать `scenes/dungeon/floor_01.tscn` — лабиринт (GridMap), тёмное освещение
- [ ] **9.2** Area3D у портала → `DungeonPortal.open_portal()` + смена сцены на floor_01
- [ ] **9.3** Создать `scripts/components/aura_component.gd` — пассивный эффект этажа в радиусе
- [ ] **9.4** Зона перехода на 2-й этаж (заблокирована до выполнения условия)
- [ ] **9.5** При закрытии портала → телепорт игрока к входу в город

---

## Этап 10 — XP и достижения

- [ ] **10.1** `scenes/ui/xp_popup.tscn` — всплывающий "+XP" над игроком при начислении
- [ ] **10.2** Уведомление "Новый уровень!" при сигнале `XPSystem.level_up`
- [ ] **10.3** `scripts/systems/achievement_system.gd` + `.tres` в `resources/achievements/`

---

## Этап 11 — Стартовые локации рас

- [ ] **11.1** `scenes/world/barbarian_camp.tscn` — шаман выдаёт татуировки (пассивные бонусы)
- [ ] **11.2** `scenes/world/elf_village.tscn` — двухуровневая деревня, Area3D-подъёмники
- [ ] **11.3** `scenes/world/demon_ruins.tscn` — NPC обрядов → `EssenceSystem.add_bonus_slot()`
- [ ] **11.4** `scenes/world/angel_citadel.tscn` — NPC жрецов → `EssenceSystem.add_bonus_slot()`
- [ ] **11.5** Переходы из каждой локации → Человеческий город

---

## Этап 12 — Расовые механики

- [ ] **12.1** Варвар: шаман выдаёт татуировки → пассивные бонусы (`scripts/races/barbarian_passives.gd`)
- [ ] **12.2** Эльф: связь с духом природы (`scripts/races/elf_passives.gd`)
- [ ] **12.3** Демон: обряд → `EssenceSystem.add_bonus_slot()` (`scripts/races/demon_ritual.gd`)
- [ ] **12.4** Ангел: аналогично + бонус к жреческим заклинаниям (`scripts/races/angel_ritual.gd`)
- [ ] **12.5** Человек: зачарование оружия у NPC-мага в городе

---

## Этап 13 — Боссы этажей

- [ ] **13.1** `scripts/entities/boss.gd` (extends Enemy) с поддержкой фаз (`phase_thresholds: Array[float]`)
- [ ] **13.2** Переход фаз по % HP: смена паттерна атак, усиление характеристик
- [ ] **13.3** `scripts/dungeon/boss_manager.gd` — проверяет условия появления босса
- [ ] **13.4** Уникальный дроп с босса через LootTable

---

## Этап 14 — Все 15 этажей подземелья

- [ ] **14.1** `scenes/dungeon/floor_02.tscn` ... `floor_15.tscn`
- [ ] **14.2** `resources/dungeon_floors/` — данные каждого этажа (аура, список монстров)
- [ ] **14.3** Прогрессия сложности: урон/HP врагов умножаются на коэффициент этажа
- [ ] **14.4** Скрытые уникальные монстры: Area3D-триггеры с условиями появления
- [ ] **14.5** Финальный 15-й этаж: особый босс + уникальная механика

---

## Этап 15 — Полировка

- [ ] **15.1** Звуки: шаги, удары, смерть, UI-клики (`AudioStreamPlayer`)
- [ ] **15.2** Частицы: удар, смерть врага, подбор предмета (`GPUParticles3D`)
- [ ] **15.3** Анимации idle / walk / attack через `AnimationPlayer`
- [ ] **15.4** Оптимизация: пул объектов для врагов, occlusion culling
