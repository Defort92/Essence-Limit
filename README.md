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

## Этап 1 — Видимая игра

- [ ] **1.1** Убедиться что `main.tscn` запускается — капсула ходит по полу, камера следит
- [ ] **1.2** Создать `scenes/ui/hud.tscn` + `scripts/ui/hud.gd` — полоска HP, золото, уровень
- [ ] **1.3** Настроить угол камеры (`offset` в `scripts/camera/game_camera.gd`)
- [ ] **1.4** Создать `scenes/characters/enemy_test.tscn` — враг ходит к игроку, бьёт, умирает
- [ ] **1.5** Мигание красным при получении урона (Tween на материале или модуляции)

---

## Этап 2 — Создание персонажа

- [ ] **2.1** Создать `scenes/ui/character_creation.tscn` — 5 кнопок рас с описанием
- [ ] **2.2** Базовые статы зависят от расы (сила, ловкость, интеллект)
- [ ] **2.3** Поле ввода имени персонажа
- [ ] **2.4** Кнопка "Начать игру" → смена сцены на стартовую локацию расы
- [ ] **2.5** Добавить в `scripts/systems/game_manager.gd` стартовые статы по расе

---

## Этап 3 — Человеческий город

- [ ] **3.1** Создать `scenes/world/human_city.tscn` — карта через GridMap (пол, стены, дорога)
- [ ] **3.2** Коллизии для стен — игрок не проходит сквозь здания
- [ ] **3.3** Создать `scripts/world/transition_zone.gd` — Area3D-переходы по углам к локациям рас
- [ ] **3.4** Создать `scripts/world/portal_zone.gd` — зона входа в подземелье (активна если портал открыт)
- [ ] **3.5** NPC-заглушки на месте торговцев и ремесленников
- [ ] **3.6** Знаки/маркеры у зон перехода

---

## Этап 4 — Боевая система

- [ ] **4.1** Добавить в `scenes/characters/player.tscn` AttackArea (Area3D перед персонажем)
- [ ] **4.2** В `scripts/entities/player.gd`: по ЛКМ — активировать Area3D, нанести урон Enemy в зоне
- [ ] **4.3** Уклонение (Пробел) — рывок + временный i-frame (неуязвимость ~0.3 сек)
- [ ] **4.4** Полоска HP над головой врага (billboard ProgressBar или Label3D)
- [ ] **4.5** Создать `scenes/characters/enemy_base.tscn` на основе `scripts/entities/enemy.gd`
- [ ] **4.6** Смерть врага: анимация исчезновения, дроп золота/эссенции-заглушки
- [ ] **4.7** Создать `scenes/ui/death_screen.tscn` — "Вы погибли" + кнопка возврата в город

---

## Этап 5 — Инвентарь и предметы

- [ ] **5.1** Создать `scenes/ui/inventory.tscn` + `scripts/ui/inventory.gd` — сетка слотов (клавиша I)
- [ ] **5.2** Слоты снаряжения: голова, тело, ноги, оружие (осн./доп. рука), 3 вспомогательных
- [ ] **5.3** Создать `scenes/world/item_pickup.tscn` + `scripts/world/item_pickup.gd` — предмет на земле, подобрать F
- [ ] **5.4** Надеть предмет → применить `stat_bonuses` из `EquipmentData`
- [ ] **5.5** Панель характеристик персонажа в инвентаре

---

## Этап 6 — Система эссенций (UI)

- [ ] **6.1** Создать `scenes/ui/essence_panel.tscn` + `scripts/ui/essence_panel.gd` — слоты (кол-во = уровень)
- [ ] **6.2** Установка эссенции: drag & drop из инвентаря в слот
- [ ] **6.3** Удаление: только в городе, за золото (`EssenceSystem.remove()` + `GameManager.spend_gold()`)
- [ ] **6.4** Отображение суммарных бонусов от вставленных эссенций
- [ ] **6.5** Создать 3–5 тестовых эссенций как `.tres` в `resources/essences/`

---

## Этап 7 — Торговля и экономика

- [ ] **7.1** Создать `scenes/ui/shop.tscn` + `scripts/ui/shop.gd` — два столбца: товары / инвентарь
- [ ] **7.2** Покупка за золото (`GameManager.spend_gold()`), продажа (`GameManager.add_gold()`)
- [ ] **7.3** Создать `scenes/world/npc_merchant.tscn` — NPC с каталогом товаров
- [ ] **7.4** NPC-ремесленник: кнопка удаления эссенции за плату

---

## Этап 8 — Подземелье: первый этаж

- [ ] **8.1** Создать `scenes/dungeon/floor_01.tscn` — лабиринт (GridMap), тёмное освещение
- [ ] **8.2** Area3D у портала → `DungeonPortal.open_portal()` + смена сцены на floor_01
- [ ] **8.3** Создать `scripts/components/aura_component.gd` — пассивный эффект этажа в радиусе
- [ ] **8.4** Создать `scripts/dungeon/dungeon_floor.gd` — менеджер этажа (аура, монстры, переходы)
- [ ] **8.5** Зона перехода на 2-й этаж (заблокирована до выполнения условия)
- [ ] **8.6** При закрытии портала (`DungeonPortal.portal_closed`) → телепорт игрока к входу

---

## Этап 9 — XP и достижения

- [ ] **9.1** Проверить что `XPSystem.try_award_kill_xp()` вызывается при смерти врага (уже в `enemy.gd`)
- [ ] **9.2** Создать `scenes/ui/xp_popup.tscn` — всплывающий "+XP" над игроком
- [ ] **9.3** Уведомление "Новый уровень!" + сигнал о новом слоте эссенции
- [ ] **9.4** Создать `scripts/systems/achievement_system.gd` + `.tres` в `resources/achievements/`
- [ ] **9.5** Экран достижений в меню

---

## Этап 10 — Стартовые локации рас

- [ ] **10.1** `scenes/world/barbarian_camp.tscn` — лесной лагерь, палатки, шаман (выдаёт татуировки)
- [ ] **10.2** `scenes/world/elf_village.tscn` — двухуровневая деревня, Area3D-подъёмники
- [ ] **10.3** `scenes/world/demon_ruins.tscn` — тёмные разрушенные постройки, NPC обрядов
- [ ] **10.4** `scenes/world/angel_citadel.tscn` — белые постройки, NPC жрецов
- [ ] **10.5** Зона перехода из каждой локации → Человеческий город

---

## Этап 11 — Расовые механики

- [ ] **11.1** Варвар: шаман выдаёт татуировки → пассивные бонусы (`scripts/races/barbarian_passives.gd`)
- [ ] **11.2** Эльф: диалог с духом природы → пассивка к дальнему бою (`scripts/races/elf_passives.gd`)
- [ ] **11.3** Демон: обряд усиления → `EssenceSystem.add_bonus_slot()` (`scripts/races/demon_ritual.gd`)
- [ ] **11.4** Ангел: аналогично + бонус к жреческим заклинаниям (`scripts/races/angel_ritual.gd`)
- [ ] **11.5** Человек: все типы оружия + зачарование у NPC-мага в городе

---

## Этап 12 — Боссы этажей

- [ ] **12.1** Создать `scripts/entities/boss.gd` (extends Enemy) с поддержкой фаз (`phase_thresholds: Array[float]`)
- [ ] **12.2** Переход фаз по % HP: смена паттерна атак, усиление характеристик
- [ ] **12.3** Создать `scripts/dungeon/boss_manager.gd` — проверяет условия появления босса на этаже
- [ ] **12.4** Уникальный дроп с босса (редкая эссенция или предмет)
- [ ] **12.5** Создать папку `scenes/dungeon/bosses/` и первую сцену босса

---

## Этап 13 — Все 15 этажей подземелья

- [ ] **13.1** Создать `scenes/dungeon/floor_02.tscn` ... `floor_15.tscn`
- [ ] **13.2** `resources/dungeon_floors/` — данные каждого этажа (аура, список монстров)
- [ ] **13.3** Прогрессия сложности: урон/HP врагов умножаются на коэффициент этажа
- [ ] **13.4** Скрытые уникальные монстры: Area3D-триггеры с условиями появления
- [ ] **13.5** Финальный 15-й этаж: особый босс + уникальная механика боя

---

## Этап 14 — Сохранение и загрузка

- [ ] **14.1** Создать `scripts/systems/save_system.gd` — сериализация в JSON (`user://save.json`)
- [ ] **14.2** Автосохранение при смене сцены
- [ ] **14.3** Создать `scenes/ui/main_menu.tscn` — Новая игра / Продолжить

---

## Этап 15 — Полировка

- [ ] **15.1** Звуки: шаги, удары, смерть, UI-клики (`AudioStreamPlayer`)
- [ ] **15.2** Частицы: удар, смерть врага, подбор предмета (`GPUParticles3D`)
- [ ] **15.3** Анимации idle / walk / attack через `AnimationPlayer`
- [ ] **15.4** Оптимизация: пул объектов для врагов, occlusion culling

---

## Текущее состояние проекта

| Система | Файл | Статус |
|---------|------|--------|
| GameManager | `scripts/systems/game_manager.gd` | ✅ базовый |
| EssenceSystem | `scripts/systems/essence_system.gd` | ✅ базовый |
| XPSystem | `scripts/systems/xp_system.gd` | ✅ базовый |
| DungeonPortal | `scripts/systems/dungeon_portal.gd` | ✅ базовый |
| Player | `scripts/entities/player.gd` | ✅ движение + dodge |
| Enemy | `scripts/entities/enemy.gd` | ✅ базовый AI |
| Camera | `scripts/camera/game_camera.gd` | ✅ следит за игроком |
| EssenceData | `scripts/data/essence_data.gd` | ✅ Resource-класс |
| EquipmentData | `scripts/data/equipment_data.gd` | ✅ Resource-класс |
| main.tscn | `scenes/main.tscn` | ✅ тестовый уровень |
| player.tscn | `scenes/characters/player.tscn` | ✅ капсула-placeholder |
