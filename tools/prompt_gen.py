#!/usr/bin/env python3
"""
Essence Limit — Sprite Prompt Generator
=========================================
Генерирует готовые промпты для Grok (изображения и видео).

Режимы:
  anchor      — базовый спрайт персонажа (вид с одного направления)
  directional — 7 оставшихся направлений на основе south anchor
  video       — видео-промпт для walk/idle (I2V в Grok)
  poseboard   — доска поз для attack/hurt/death/jump (статичная генерация)
  list        — показать все доступные персонажи и анимации

Примеры:
  python prompt_gen.py anchor --char base --dir s
  python prompt_gen.py anchor --char elf --dir s
  python prompt_gen.py directional --char barbarian --dir w
  python prompt_gen.py video --char human_warrior --anim walk --dir s
  python prompt_gen.py poseboard --char demon --anim attack --dir w
  python prompt_gen.py list
"""

import argparse
import sys
import textwrap

# Fix Windows console encoding
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout.reconfigure(encoding="utf-8")

# ═══════════════════════════════════════════════════════════════════════════════
#   ОПИСАНИЯ ПЕРСОНАЖЕЙ
# ═══════════════════════════════════════════════════════════════════════════════

CHARACTERS = {
    # Абстрактный манекен — основа, от которой генерируются все расы
    "base": {
        "label": "Базовый манекен",
        "body": "gender-neutral humanoid figure, average height and build",
        "outfit": "plain tight-fitting dark grey bodysuit, no armor, no accessories",
        "weapon": "no weapon, arms at sides",
        "race_features": "no special features, smooth face, short dark hair",
        "palette_hint": "8 colors maximum. Grayscale-dominant with dark grey, charcoal, and off-white accents.",
        "style_note": "This is a template mannequin. Keep it deliberately plain and minimal — it serves as a proportion reference for all other characters.",
    },

    "human_warrior": {
        "label": "Человек — воин",
        "body": "human male, medium athletic build, average height",
        "outfit": "dark iron plate armor, worn and battle-scarred, leather straps, simple pauldrons",
        "weapon": "one-handed longsword in right hand (or at hip in idle), small round steel shield on left arm",
        "race_features": "no special features, short brown hair, determined expression",
        "palette_hint": "12 colors. Dark iron grey, leather brown, muted silver highlights, dark red trim.",
        "style_note": "Classic dark fantasy warrior. Armor looks functional and worn, not ornate.",
    },

    "human_wizard": {
        "label": "Человек — волшебник",
        "body": "human male or female, slim build, slightly taller than average",
        "outfit": "dark teal hooded robe with faint arcane rune embroidery, leather belt, no heavy armor",
        "weapon": "wooden staff topped with a glowing amber crystal orb, held in right hand",
        "race_features": "no special features, pale complexion, partially visible face under hood",
        "palette_hint": "12 colors. Deep teal, dark navy, amber glow accent, pale skin, dark wood brown.",
        "style_note": "Robes should read clearly as magical but not flashy. Runes are subtle texture, not glowing lines.",
    },

    "elf": {
        "label": "Эльф — лучник",
        "body": "elf female or male, very slim and tall build, slightly longer limbs",
        "outfit": "fitted forest-green leather scout armor, bracers, thin shoulder guard, no bulky pauldrons",
        "weapon": "recurve longbow across back, quiver of arrows on right hip",
        "race_features": "long pointed ears, slightly angular face, faintly luminous green or silver eyes, long braided hair",
        "palette_hint": "12 colors. Forest green, dark olive, brown leather, pale ivory skin, subtle silver accent.",
        "style_note": "Silhouette should feel light and agile. Ears clearly visible and readable even at small size.",
    },

    "barbarian": {
        "label": "Варвар — танк",
        "body": "barbarian male, very large and muscular build, shorter neck, wide shoulders",
        "outfit": "fur-trimmed leather vest, leather bracers, no shirt, rough hide trousers, heavy boots",
        "weapon": "massive two-handed war axe carried on back (or held two-handed in action poses)",
        "race_features": "tribal tattoos covering both arms and parts of neck and chest (dark ink lines, angular patterns), rough face, long braided red or black hair",
        "palette_hint": "12 colors. Dark leather brown, fur grey-white, dark red war paint, deep black tattoo lines, ruddy skin tone.",
        "style_note": "Silhouette should feel wide and heavy. Tattoos must be readable as simple angular lines at sprite scale.",
    },

    "demon": {
        "label": "Демон — ДПС",
        "body": "demon male, lean and agile athletic build, slightly taller than human",
        "outfit": "dark obsidian scale armor on chest and shoulders, bare forearms, black leather trousers, clawed boots",
        "weapon": "curved single-edged blade (falchion) in right hand, short blade at hip",
        "race_features": "two curved horns on head, dark charcoal-grey skin with subtle red vein patterns, glowing amber or red eyes, black sclera",
        "palette_hint": "12 colors. Obsidian black, dark charcoal skin, deep crimson accent, amber eye glow, dull silver blade.",
        "style_note": "Menacing but agile silhouette. Horns must be clearly readable. Red accents minimal — only veins and eyes.",
    },

    "angel": {
        "label": "Ангел — маг/дальний бой",
        "body": "angel female or male, slim graceful build, average height",
        "outfit": "white and pale gold plate armor, light and elegant design, simple breastplate with wing motif, no bulk",
        "weapon": "radiant spear held in right hand, or shortbow across back (specify per animation)",
        "race_features": "two large folded feathered wings on back (white with pale gold tips), soft glowing pale skin, silver or blonde hair, serene expression",
        "palette_hint": "12 colors. Pure white, pale gold, soft ivory, silver, muted sky blue accent, warm skin tone.",
        "style_note": "Wings must be visibly folded against back in idle/walk — not spread. Spread only in specific ability animations.",
    },
}

# ═══════════════════════════════════════════════════════════════════════════════
#   НАПРАВЛЕНИЯ
# ═══════════════════════════════════════════════════════════════════════════════

DIRECTIONS = {
    "s":  ("south",     "facing directly toward the viewer, full front view"),
    "n":  ("north",     "facing directly away from the viewer, full back view"),
    "e":  ("east",      "facing right, full side profile"),
    "w":  ("west",      "facing left, full side profile"),
    "se": ("southeast", "facing toward viewer at 45-degree angle, slightly right, 3/4 front view"),
    "sw": ("southwest", "facing toward viewer at 45-degree angle, slightly left, 3/4 front view"),
    "ne": ("northeast", "facing away from viewer at 45-degree angle, slightly right, 3/4 back view"),
    "nw": ("northwest", "facing away from viewer at 45-degree angle, slightly left, 3/4 back view"),
}

# ═══════════════════════════════════════════════════════════════════════════════
#   АНИМАЦИИ
# ═══════════════════════════════════════════════════════════════════════════════

ANIMATIONS = {
    "idle": {
        "label": "Idle (простой)",
        "method": "video",
        "frames": 8,
        "fps": 8,
        "video_motion": "very subtle breathing in-place. Chest rises by 1-2 pixels and falls. Slight weight shift. No footsteps. Absolutely no horizontal drift.",
        "poseboard_frames": (
            "Frame 1: base relaxed stance, feet slightly apart\n"
            "Frame 2: chest slightly raised (inhale start)\n"
            "Frame 3: chest at maximum rise (full inhale)\n"
            "Frame 4: holding breath, slight upward lean\n"
            "Frame 5: beginning exhale, chest drops\n"
            "Frame 6: mid exhale\n"
            "Frame 7: full exhale, slight downward settle\n"
            "Frame 8: return to base stance (same as frame 1)"
        ),
    },
    "walk": {
        "label": "Walk (ходьба)",
        "method": "video",
        "frames": 8,
        "fps": 10,
        "video_motion": "in-place walk cycle. Alternating left and right leg steps. Counter-swinging arms (left arm forward when right leg forward). Character remains perfectly centered — no horizontal drift, no bobbing, no rotation, no scale change.",
        "poseboard_frames": (
            "Frame 1: left foot forward, right arm forward (stride extreme)\n"
            "Frame 2: weight transferring, feet passing\n"
            "Frame 3: neutral upright stance (mid-stride)\n"
            "Frame 4: right foot forward, left arm forward (stride extreme)\n"
            "Frame 5: weight transferring back, feet passing\n"
            "Frame 6: neutral upright stance (mid-stride)\n"
            "Frame 7: left foot forward again (cycle repeat start)\n"
            "Frame 8: transition back to frame 1"
        ),
    },
    "attack": {
        "label": "Attack (атака)",
        "method": "poseboard",
        "frames": 8,
        "fps": 12,
        "video_motion": "one sharp weapon attack strike. Wind up then fast swing. Return to stance.",
        "poseboard_frames": (
            "Frame 1: idle ready stance, weapon at rest\n"
            "Frame 2: wind-up — weapon pulled back, body rotated opposite\n"
            "Frame 3: beginning of swing, body rotating forward\n"
            "Frame 4: mid-swing, weapon arc at 45 degrees, full body rotation\n"
            "Frame 5: IMPACT frame — weapon at maximum extension, body weight fully forward\n"
            "Frame 6: follow-through, weapon past impact point\n"
            "Frame 7: recovery — weapon returning, body straightening\n"
            "Frame 8: back to idle ready stance (same as frame 1)"
        ),
    },
    "hurt": {
        "label": "Hurt (получение урона)",
        "method": "poseboard",
        "frames": 6,
        "fps": 12,
        "video_motion": "hit reaction: head snaps back, body recoils, then recovers.",
        "poseboard_frames": (
            "Frame 1: idle stance before hit\n"
            "Frame 2: IMPACT — head snapping back, body twisting from the hit, arms flailing outward\n"
            "Frame 3: maximum recoil — body leaning backward, staggering\n"
            "Frame 4: stumbling, trying to regain balance, still leaning back\n"
            "Frame 5: recovering, body returning to center, arms lowering\n"
            "Frame 6: back to idle stance, slightly shaken"
        ),
    },
    "death": {
        "label": "Death (смерть)",
        "method": "poseboard",
        "frames": 10,
        "fps": 10,
        "video_motion": "fatal hit, then slow fall and collapse to the ground. Character lands face-down or sideways and is motionless.",
        "poseboard_frames": (
            "Frame 1: idle standing\n"
            "Frame 2: death blow impact — violent recoil, expression of shock\n"
            "Frame 3: knees beginning to buckle, body sagging\n"
            "Frame 4: half-kneeling, one knee on ground, arms going limp\n"
            "Frame 5: tilting forward into fall\n"
            "Frame 6: falling forward, arms not bracing — body limp\n"
            "Frame 7: mid-fall, horizontal\n"
            "Frame 8: ground impact, slight dust or impact visual\n"
            "Frame 9: final adjustment settle (small shift after landing)\n"
            "Frame 10: completely still on ground, final death pose"
        ),
    },
    "jump": {
        "label": "Jump (прыжок)",
        "method": "poseboard",
        "frames": 6,
        "fps": 12,
        "video_motion": "jump up and land. Knees bend, then push off, reach apex, then descend and land with bent knees.",
        "poseboard_frames": (
            "Frame 1: crouch preparation — knees bent, arms pulled back\n"
            "Frame 2: launch — feet leaving ground, legs extended downward, arms swinging up\n"
            "Frame 3: ascent — body rising, legs tucking slightly\n"
            "Frame 4: APEX — maximum height, legs partially tucked, arms raised\n"
            "Frame 5: descent — body falling, legs extending downward to prepare landing\n"
            "Frame 6: landing — knees bent absorbing impact, arms out for balance"
        ),
    },
}

# ═══════════════════════════════════════════════════════════════════════════════
#   ШАБЛОНЫ ПРОМПТОВ
# ═══════════════════════════════════════════════════════════════════════════════

ANCHOR_TEMPLATE = """\
[IMAGE GENERATION — {label} / South Anchor]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Single full-body character sprite, {dir_name} ({dir_desc}).
Canvas: 1024×1024 pixels. Background: solid bright green #00FF00. Nothing else in the image.

── CHARACTER ──────────────────────────────────
Body:    {body}
Outfit:  {outfit}
Weapon:  {weapon}
Race:    {race_features}

── PIXEL ART STYLE (strict — do not deviate) ──
- Dark fantasy pixel art. Hard pixel edges only. Zero anti-aliasing, zero soft gradients.
- Color palette: {palette_hint}
- No glow effects, no painterly blending, no tiny jewelry or ornate details.
- Readable silhouette at thumbnail scale. Bold chunky pixel clusters.
- Proportions: slightly heroic. Head approximately 1/5 of total body height.
- Idle relaxed pose. Arms slightly away from body. Feet flat on ground.
- Character centered horizontally. Feet in lower quarter of canvas.
- Pure #00FF00 fill everywhere outside the character. No floor, no shadow, no background.

── NOTE ───────────────────────────────────────
{style_note}
"""

DIRECTIONAL_TEMPLATE = """\
[IMAGE GENERATION — {label} / Directional Anchor]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠ ATTACH the processed south anchor PNG as the image reference before sending this prompt.

Using the attached sprite as the EXACT identity reference, generate the same character
facing {dir_name} ({dir_desc}).

Canvas: 1024×1024 pixels. Background: solid bright green #00FF00.

── IDENTITY RULES (must not change) ──────────
- Preserve exact proportions, build, outfit, and color palette from the reference.
- Same armor, same weapon. Weapon must be one continuous unbroken shape — no split segments.
- Same pixel art style, same color count, same pixel cluster size.
- If the reference shows tribal tattoos / horns / wings / ears — preserve them fully.

── DIRECTION ──────────────────────────────────
Show the character facing {dir_name} ({dir_desc}).
{"East is a mirror of West — flip horizontally if easier." if dir_key == "e" else ""}
{"For diagonal views show 3/4 perspective — character slightly angled, not fully profile." if dir_key in ("ne","nw","se","sw") else ""}

── PIXEL ART STYLE ────────────────────────────
- Hard pixel edges only. No anti-aliasing.
- Character centered horizontally. Feet in lower quarter of canvas.
- Pure #00FF00 everywhere outside the character.
"""

VIDEO_TEMPLATE = """\
[VIDEO GENERATION — {label} / {anim_label} / {dir_name}]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠ ATTACH the processed directional anchor PNG ({dir_key}) as the reference image before sending.

Generate a 6-second image-to-video clip from the attached anchor image.

── SUBJECT ────────────────────────────────────
Same character as the input image. {dir_name}-facing ({dir_desc}).

── MOTION ─────────────────────────────────────
{video_motion}

── CONSTRAINTS (critical) ─────────────────────
- Character must remain centered. No horizontal drift. No rotation. No scale change.
- Character must not jump out of frame or move toward edges.
- Foot position stays approximately fixed on the same horizontal baseline throughout.
- No camera movement. Static camera, fixed frame.
- Background: keep input chroma green (#00FF00) unchanged across all frames.

── STYLE ──────────────────────────────────────
- Preserve input pixel art style throughout the entire clip.
- Hard pixel edges. No painterly motion blur. No soft transitions between pixels.
- Color palette stays locked to the reference — no new colors appear mid-clip.

── FRAME EXTRACTION NOTE ──────────────────────
After generation, extract {frames} evenly spaced frames covering one complete motion cycle:
  Start: first extreme pose (e.g. left foot forward)
  End:   return to the same extreme pose (full cycle)
  Drop all frames outside [start, end].
Target: {frames} frames at {fps} fps for the final spritesheet.
"""

POSEBOARD_TEMPLATE = """\
[IMAGE GENERATION — {label} / {anim_label} Pose Board]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠ ATTACH the processed directional anchor PNG ({dir_key}) as the reference image before sending.

Generate a 2048×1536 PNG pose board on solid bright green background #00FF00.
Grid: 4 columns × 3 rows. Each cell: 512×512 pixels. Total cells: 12.

── REFERENCE ──────────────────────────────────
Use the attached sprite as the EXACT character identity.
Same proportions, outfit, weapon, color palette, and pixel art style throughout ALL frames.

── ANIMATION ──────────────────────────────────
Animation type: {anim_label}
Character facing: {dir_name} ({dir_desc})

── FRAME SEQUENCE ({frames} frames) ───────────
{poseboard_frames}
{empty_cells_note}

── PIXEL ART RULES ────────────────────────────
- Hard pixel edges only. No anti-aliasing. Same pixel cluster size as reference.
- Color palette locked — no new colors between frames.
- Character may extend slightly outside cell bounds — do NOT crop at cell edges.
- Leave solid #00FF00 in unused cells (cells {frames_plus_one}–12).
- Do NOT draw grid lines. Background is flat green, cells implied by layout only.

── CRITICAL ───────────────────────────────────
Do not grid-slice this output. The build_spritesheet.py script handles frame recovery.
Each frame will be individually pixel-snapped and foot-normalized before packing.
"""

# ═══════════════════════════════════════════════════════════════════════════════
#   ГЕНЕРАТОР
# ═══════════════════════════════════════════════════════════════════════════════

def build_anchor_prompt(char_key: str, dir_key: str) -> str:
    char = CHARACTERS[char_key]
    dir_name, dir_desc = DIRECTIONS[dir_key]
    return ANCHOR_TEMPLATE.format(
        label=char["label"],
        dir_name=dir_name,
        dir_desc=dir_desc,
        body=char["body"],
        outfit=char["outfit"],
        weapon=char["weapon"],
        race_features=char["race_features"],
        palette_hint=char["palette_hint"],
        style_note=char["style_note"],
    )


def build_directional_prompt(char_key: str, dir_key: str) -> str:
    char = CHARACTERS[char_key]
    dir_name, dir_desc = DIRECTIONS[dir_key]
    return DIRECTIONAL_TEMPLATE.format(
        label=char["label"],
        dir_name=dir_name,
        dir_desc=dir_desc,
        dir_key=dir_key,
    )


def build_video_prompt(char_key: str, anim_key: str, dir_key: str) -> str:
    char = CHARACTERS[char_key]
    anim = ANIMATIONS[anim_key]
    dir_name, dir_desc = DIRECTIONS[dir_key]
    return VIDEO_TEMPLATE.format(
        label=char["label"],
        anim_label=anim["label"],
        dir_name=dir_name,
        dir_desc=dir_desc,
        dir_key=dir_key,
        video_motion=anim["video_motion"],
        frames=anim["frames"],
        fps=anim["fps"],
    )


def build_poseboard_prompt(char_key: str, anim_key: str, dir_key: str) -> str:
    char = CHARACTERS[char_key]
    anim = ANIMATIONS[anim_key]
    dir_name, dir_desc = DIRECTIONS[dir_key]
    frames = anim["frames"]
    empty_note = (
        f"\nCells {frames + 1}–12: leave as solid #00FF00 (empty)."
        if frames < 12 else ""
    )
    return POSEBOARD_TEMPLATE.format(
        label=char["label"],
        anim_label=anim["label"],
        dir_name=dir_name,
        dir_desc=dir_desc,
        dir_key=dir_key,
        frames=frames,
        poseboard_frames=anim["poseboard_frames"],
        empty_cells_note=empty_note,
        frames_plus_one=frames + 1,
    )


# ═══════════════════════════════════════════════════════════════════════════════
#   ИНТЕРАКТИВНОЕ МЕНЮ
# ═══════════════════════════════════════════════════════════════════════════════

W = 62  # ширина рамки

MODES = [
    ("anchor",      "Anchor       — базовый спрайт (вид спереди)"),
    ("directional", "Directional  — другое направление  [нужен anchor]"),
    ("video",       "Видео        — walk / idle  (I2V в Grok)"),
    ("poseboard",   "Pose Board   — attack / hurt / death / jump"),
]

# Направления сгруппированы для наглядности
DIR_GROUPS = [
    [("s", "South — прямо на зрителя (спереди)"),
     ("n", "North — спиной к зрителю (сзади)")],
    [("e", "East  — профиль вправо"),
     ("w", "West  — профиль влево")],
    [("se", "SE — 3/4 спереди-право"),
     ("sw", "SW — 3/4 спереди-лево")],
    [("ne", "NE — 3/4 сзади-право"),
     ("nw", "NW — 3/4 сзади-лево")],
]
# Плоский список для индексации по цифре
DIR_LIST = [item for group in DIR_GROUPS for item in group]

CHAR_LIST = list(CHARACTERS.items())   # [(key, data), ...]
ANIM_LIST = list(ANIMATIONS.items())   # [(key, data), ...]


def cls():
    """Очистить экран."""
    import os
    os.system("cls" if os.name == "nt" else "clear")


def header(breadcrumb: list[str] = None):
    """Верхняя рамка с заголовком и хлебными крошками."""
    print("╔" + "═" * W + "╗")
    title = "  ESSENCE LIMIT  —  Генератор промптов для Grok  "
    print("║" + title.center(W) + "║")
    print("╠" + "═" * W + "╣")
    if breadcrumb:
        crumb = "  " + "  ›  ".join(breadcrumb)
        print("║" + crumb.ljust(W) + "║")
        print("╠" + "─" * W + "╣")


def footer(hint: str = ""):
    print("╠" + "─" * W + "╣")
    if hint:
        print("║  " + hint.ljust(W - 2) + "║")
    print("╚" + "═" * W + "╝")


def menu_line(idx: int, text: str, tag: str = ""):
    num = f"  {idx}."
    tag_str = f"  {tag}" if tag else ""
    line = f"{num}  {text}{tag_str}"
    print("║" + line.ljust(W) + "║")


def separator():
    print("║" + "─" * W + "║")


def ask(prompt_text: str, valid: set, allow_back: bool = True) -> str | None:
    """
    Запросить ввод. Возвращает строку из valid, или None если пользователь
    ввёл 'b' (назад) или '0' (в начало).
    """
    back_hint = "  [b — назад  |  0 — в начало  |  q — выход]"
    print("║" + back_hint.ljust(W) + "║")
    footer()
    while True:
        try:
            raw = input(f"\n{prompt_text}: ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\nВыход.")
            sys.exit(0)

        if raw == "q":
            print("Выход.")
            sys.exit(0)
        if raw == "0":
            return "__restart__"
        if allow_back and raw == "b":
            return "__back__"
        if raw in valid:
            return raw
        print(f"  ⚠  Введи одну из цифр: {', '.join(sorted(valid, key=int))}")


# ── Шаг 1: Режим ─────────────────────────────────────────────────────────────

def step_mode() -> str | None:
    cls()
    header()
    print("║" + "  ШАГ 1 / 4  —  Что генерируем?".ljust(W) + "║")
    separator()
    for i, (_, label) in enumerate(MODES, 1):
        menu_line(i, label)
    valid = {str(i) for i in range(1, len(MODES) + 1)}
    result = ask("Введи цифру", valid, allow_back=False)
    if result in ("__restart__", "__back__"):
        return None
    return MODES[int(result) - 1][0]


# ── Шаг 2: Персонаж ──────────────────────────────────────────────────────────

def step_char(breadcrumb: list[str]) -> str | None:
    cls()
    header(breadcrumb)
    print("║" + "  ШАГ 2 / 4  —  Персонаж".ljust(W) + "║")
    separator()

    # Показываем базового манекена отдельно
    menu_line(1, f"{CHAR_LIST[0][1]['label']}", "← начинай отсюда")
    separator()
    for i, (_, data) in enumerate(CHAR_LIST[1:], 2):
        menu_line(i, data["label"])

    valid = {str(i) for i in range(1, len(CHAR_LIST) + 1)}
    result = ask("Введи цифру", valid)
    if result in ("__restart__", "__back__"):
        return result
    return CHAR_LIST[int(result) - 1][0]


# ── Шаг 3: Направление ───────────────────────────────────────────────────────

def step_direction(breadcrumb: list[str], exclude_south: bool = False) -> str | None:
    cls()
    header(breadcrumb)
    label = "  ШАГ 3 / 4  —  Направление"
    if exclude_south:
        label += "  (South уже есть — anchor)"
    print("║" + label.ljust(W) + "║")
    separator()

    shown = []
    for group in DIR_GROUPS:
        for key, desc in group:
            if exclude_south and key == "s":
                continue
            shown.append((key, desc))
        separator()

    # Перенумеровать после возможного исключения South
    for i, (_, desc) in enumerate(shown, 1):
        menu_line(i, desc)

    valid = {str(i) for i in range(1, len(shown) + 1)}
    result = ask("Введи цифру", valid)
    if result in ("__restart__", "__back__"):
        return result
    return shown[int(result) - 1][0]


# ── Шаг 4: Анимация ──────────────────────────────────────────────────────────

def step_animation(breadcrumb: list[str], mode: str) -> str | None:
    """Показывает только анимации, подходящие для выбранного режима."""
    cls()
    header(breadcrumb)
    print("║" + "  ШАГ 4 / 4  —  Анимация".ljust(W) + "║")
    separator()

    # Рекомендованные для режима
    recommended = [
        (key, data) for key, data in ANIM_LIST
        if (mode == "video" and data["method"] == "video") or
           (mode == "poseboard" and data["method"] == "poseboard")
    ]
    other = [
        (key, data) for key, data in ANIM_LIST
        if (key, data) not in recommended
    ]

    shown = []
    tag_rec = "✓ рекомендовано"
    tag_alt = "можно, но хуже"
    for key, data in recommended:
        shown.append((key, data, tag_rec))
        menu_line(len(shown), f"{data['label']}  ({data['frames']} кадров @ {data['fps']} fps)", tag_rec)

    if other:
        separator()
        print("║" + "  Другие (не оптимальный метод):".ljust(W) + "║")
        for key, data in other:
            shown.append((key, data, tag_alt))
            menu_line(len(shown), f"{data['label']}  ({data['frames']} кадров @ {data['fps']} fps)", tag_alt)

    valid = {str(i) for i in range(1, len(shown) + 1)}
    result = ask("Введи цифру", valid)
    if result in ("__restart__", "__back__"):
        return result
    return shown[int(result) - 1][0]


# ── Показ промпта + меню действий ────────────────────────────────────────────

def show_prompt(prompt: str, info: str, has_anim: bool) -> str:
    """
    Возвращает действие:
      'new'  — начать сначала (с шага 1)
      'mode' — сменить режим (= тоже шаг 1, синоним)
      'char' — сменить персонажа (с шага 2)
      'dir'  — сменить направление (с шага 3)
      'anim' — сменить анимацию (с шага 4, только если has_anim)
      'quit' — выйти
    """
    cls()
    sep = "═" * W
    print(f"\n{sep}")
    print(prompt)
    print(sep)
    print(f"\n  {info}\n")
    print("  Что дальше?")
    print("  ─────────────────────────────────────────")
    print("  1.  Сменить НАПРАВЛЕНИЕ  (тот же персонаж и режим)")
    print("  2.  Сменить ПЕРСОНАЖА   (тот же режим)")
    if has_anim:
        print("  3.  Сменить АНИМАЦИЮ    (тот же персонаж и направление)")
        print("  4.  Сменить РЕЖИМ       (начать сначала)")
        print("  5.  Выйти")
        valid = {"1", "2", "3", "4", "5", "q"}
        mapping = {"1": "dir", "2": "char", "3": "anim", "4": "new", "5": "quit", "q": "quit"}
    else:
        print("  3.  Сменить РЕЖИМ       (начать сначала)")
        print("  4.  Выйти")
        valid = {"1", "2", "3", "4", "q"}
        mapping = {"1": "dir", "2": "char", "3": "new", "4": "quit", "q": "quit"}

    print()
    while True:
        try:
            raw = input("Введи цифру: ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            sys.exit(0)
        if raw in valid:
            action = mapping[raw]
            if action == "quit":
                print("Выход.")
                sys.exit(0)
            return action
        print(f"  ⚠  Введи одну из: {', '.join(sorted(valid))}")


# ── Главный интерактивный цикл (state-machine) ───────────────────────────────

def _crumb(state: dict) -> list[str]:
    """Построить хлебные крошки из текущего состояния."""
    crumbs = []
    if state["mode"]:
        crumbs.append(next(label for key, label in MODES if key == state["mode"]).split("—")[0].strip())
    if state["char"]:
        crumbs.append(CHARACTERS[state["char"]]["label"])
    if state["dir"]:
        crumbs.append(DIRECTIONS[state["dir"]][0].capitalize())
    if state["anim"]:
        crumbs.append(ANIMATIONS[state["anim"]]["label"])
    return crumbs


def run_interactive():
    state = {"mode": None, "char": None, "dir": None, "anim": None}
    start_from = 1   # с какого шага начинать

    while True:
        # ── ШАГ 1 — Режим ────────────────────────────────────────────────────
        if start_from <= 1:
            mode = step_mode()
            if mode is None:
                start_from = 1
                continue
            # Сброс зависимых полей при смене режима
            if state["mode"] != mode:
                state["char"] = None
                state["dir"] = None
                state["anim"] = None
            state["mode"] = mode

        # ── ШАГ 2 — Персонаж ─────────────────────────────────────────────────
        if start_from <= 2:
            char_key = step_char(_crumb(state))
            if char_key == "__restart__":
                state = {"mode": None, "char": None, "dir": None, "anim": None}
                start_from = 1
                continue
            if char_key == "__back__":
                start_from = 1
                continue
            state["char"] = char_key

        # ── ШАГ 3 — Направление ──────────────────────────────────────────────
        if start_from <= 3:
            exclude_s = (state["mode"] == "directional")
            dir_key = step_direction(_crumb(state), exclude_south=exclude_s)
            if dir_key == "__restart__":
                state = {"mode": None, "char": None, "dir": None, "anim": None}
                start_from = 1
                continue
            if dir_key == "__back__":
                start_from = 2
                continue
            state["dir"] = dir_key

        # ── ШАГ 4 — Анимация (только video / poseboard) ──────────────────────
        needs_anim = state["mode"] in ("video", "poseboard")
        if needs_anim and start_from <= 4:
            anim_key = step_animation(_crumb(state), state["mode"])
            if anim_key == "__restart__":
                state = {"mode": None, "char": None, "dir": None, "anim": None}
                start_from = 1
                continue
            if anim_key == "__back__":
                start_from = 3
                continue
            state["anim"] = anim_key
        elif not needs_anim:
            state["anim"] = None

        # ── Собрать промпт ───────────────────────────────────────────────────
        mode = state["mode"]
        char_key = state["char"]
        dir_key = state["dir"]
        anim_key = state["anim"]

        char_label = CHARACTERS[char_key]["label"]
        dir_label = DIRECTIONS[dir_key][0].capitalize()

        if mode == "anchor":
            prompt = build_anchor_prompt(char_key, dir_key)
            info = f"Персонаж: {char_label}  |  Anchor  |  Направление: {dir_label}"

        elif mode == "directional":
            prompt = build_directional_prompt(char_key, dir_key)
            info = f"Персонаж: {char_label}  |  Directional  |  Направление: {dir_label}"

        elif mode == "video":
            anim_label = ANIMATIONS[anim_key]["label"]
            prompt = build_video_prompt(char_key, anim_key, dir_key)
            info = f"Персонаж: {char_label}  |  Видео  |  {anim_label}  |  {dir_label}"

        elif mode == "poseboard":
            anim_label = ANIMATIONS[anim_key]["label"]
            prompt = build_poseboard_prompt(char_key, anim_key, dir_key)
            info = f"Персонаж: {char_label}  |  Pose Board  |  {anim_label}  |  {dir_label}"

        # ── Меню действий после показа промпта ───────────────────────────────
        action = show_prompt(prompt, info, has_anim=needs_anim)

        if action == "new":
            state = {"mode": None, "char": None, "dir": None, "anim": None}
            start_from = 1
        elif action == "char":
            state["char"] = None
            state["anim"] = None if not needs_anim else state["anim"]
            start_from = 2
        elif action == "dir":
            state["dir"] = None
            start_from = 3
        elif action == "anim":
            state["anim"] = None
            start_from = 4


# ─── Точка входа ──────────────────────────────────────────────────────────────

def main():
    # Если аргументов нет — запустить интерактивное меню
    if len(sys.argv) == 1:
        run_interactive()
        return

    # Иначе — старый CLI (для скриптов/автоматизации)
    parser = argparse.ArgumentParser(
        description="Essence Limit — генератор промптов для Grok",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""
        Без аргументов запускается интерактивное меню.
        Примеры CLI:
          python prompt_gen.py anchor --char base --dir s
          python prompt_gen.py directional --char elf --dir w
          python prompt_gen.py video --char human_warrior --anim walk --dir s
          python prompt_gen.py poseboard --char demon --anim attack --dir w
        """),
    )
    subparsers = parser.add_subparsers(dest="mode", required=True)

    p_a = subparsers.add_parser("anchor")
    p_a.add_argument("--char", required=True, choices=list(CHARACTERS))
    p_a.add_argument("--dir",  required=True, choices=list(DIRECTIONS))

    p_d = subparsers.add_parser("directional")
    p_d.add_argument("--char", required=True, choices=list(CHARACTERS))
    p_d.add_argument("--dir",  required=True, choices=list(DIRECTIONS))

    p_v = subparsers.add_parser("video")
    p_v.add_argument("--char", required=True, choices=list(CHARACTERS))
    p_v.add_argument("--anim", required=True, choices=list(ANIMATIONS))
    p_v.add_argument("--dir",  required=True, choices=list(DIRECTIONS))

    p_p = subparsers.add_parser("poseboard")
    p_p.add_argument("--char", required=True, choices=list(CHARACTERS))
    p_p.add_argument("--anim", required=True, choices=list(ANIMATIONS))
    p_p.add_argument("--dir",  required=True, choices=list(DIRECTIONS))

    args = parser.parse_args()

    if args.mode == "anchor":
        prompt = build_anchor_prompt(args.char, args.dir)
        info = f"anchor | {args.char} | {args.dir}"
    elif args.mode == "directional":
        prompt = build_directional_prompt(args.char, args.dir)
        info = f"directional | {args.char} | {args.dir}"
    elif args.mode == "video":
        prompt = build_video_prompt(args.char, args.anim, args.dir)
        info = f"video | {args.char} | {args.anim} | {args.dir}"
    elif args.mode == "poseboard":
        prompt = build_poseboard_prompt(args.char, args.anim, args.dir)
        info = f"poseboard | {args.char} | {args.anim} | {args.dir}"

    sep = "═" * 60
    print(f"\n{sep}\n{prompt}\n{sep}\n[{info}]")


if __name__ == "__main__":
    main()
