#!/usr/bin/env python3
"""
Essence Limit — PixelLab Image Generator
=========================================
Использует те же шаги выбора, что и prompt_gen.py (режим / персонаж /
направление), но вместо вывода Grok-промпта собирает компактное описание
для PixelLab API и сохраняет результат в выбранную папку.

Запуск:
    set PIXELLAB_API_KEY=ваш_ключ        (Windows cmd)
    $env:PIXELLAB_API_KEY="ваш_ключ"     (PowerShell)
    export PIXELLAB_API_KEY=ваш_ключ     (bash)
    python pixellab_gen.py

Зависимости:
    pip install pixellab Pillow
"""

import json
import os
import random
import sys
from pathlib import Path
from typing import Optional

# Fix Windows console encoding
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout.reconfigure(encoding="utf-8")

# Импорт состояния, словарей и UI-помощников из prompt_gen
sys.path.insert(0, str(Path(__file__).parent))
from prompt_gen import (
    CHARACTERS,
    DIRECTIONS,
    W,
    _crumb,
    ask,
    cls,
    footer,
    header,
    menu_line,
    separator,
    step_char,
    step_direction,
)

# PixelLab SDK
try:
    import pixellab
except ImportError:
    print("Не установлен pixellab SDK.\n" "  Поставь:  pip install pixellab")
    sys.exit(1)


# ═══════════════════════════════════════════════════════════════════════════════
#   КОНФИГ
# ═══════════════════════════════════════════════════════════════════════════════

# Только режимы, имеющие смысл для PixelLab text→image
PIXELLAB_MODES = [
    ("anchor", "Anchor       — спрайт по описанию (text → image)"),
    ("directional", "Directional  — тот же персонаж в другом направлении"),
]

# Пути к .env и файлу состояния ключей
TOOLS_DIR = Path(__file__).parent
ENV_PATH = TOOLS_DIR / ".env"
STATE_PATH = TOOLS_DIR / ".pixellab_keys_state.json"


# ═══════════════════════════════════════════════════════════════════════════════
#   .env ПАРСЕР И МЕНЕДЖЕР КЛЮЧЕЙ
# ═══════════════════════════════════════════════════════════════════════════════


def _parse_env_file(path: Path) -> dict:
    """Мини-парсер .env (KEY=VALUE построчно, # — комментарии)."""
    data = {}
    if not path.exists():
        return data
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, _, val = line.partition("=")
        name = name.strip()
        val = val.strip().strip('"').strip("'")
        if name:
            data[name] = val
    return data


def _collect_keys() -> list[str]:
    """Загрузить ключи из PIXELLAB_API_KEYS (через запятую).
    Источники: env var и tools/.env (env var имеет приоритет)."""
    raw = os.environ.get("PIXELLAB_API_KEYS", "").strip()
    if not raw:
        raw = _parse_env_file(ENV_PATH).get("PIXELLAB_API_KEYS", "").strip()
    keys = [k.strip() for k in raw.split(",") if k.strip()]
    # Дедупликация с сохранением порядка
    seen, out = set(), []
    for k in keys:
        if k not in seen:
            seen.add(k)
            out.append(k)
    return out


class KeyManager:
    """Хранит список ключей, помечает израсходованные в локальном json-файле,
    отдаёт следующий доступный."""

    # Подстроки в сообщении ошибки → пометить ключ как израсходованный
    EXHAUST_MARKERS = (
        "402",
        "insufficient",
        "no credits",
        "out of credits",
        "quota",
        "limit reached",
        "limit exceeded",
        "payment required",
        "no generations",
        "exhausted",
        "balance",
    )
    INVALID_MARKERS = (
        "401",
        "unauthorized",
        "invalid api key",
        "invalid key",
        "forbidden",
        "403",
    )
    RATELIMIT_MARKERS = ("429", "rate limit", "too many requests")

    def __init__(self):
        self.all_keys: list[str] = _collect_keys()
        self.state: dict = self._load_state()
        ex = set(self.state.get("exhausted", []))
        self.active: list[str] = [k for k in self.all_keys if k not in ex]
        self.idx: int = 0

    def _load_state(self) -> dict:
        if STATE_PATH.exists():
            try:
                return json.loads(STATE_PATH.read_text(encoding="utf-8"))
            except Exception:
                pass
        return {"exhausted": []}

    def _save_state(self):
        STATE_PATH.write_text(
            json.dumps(self.state, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

    def current(self) -> Optional[str]:
        if 0 <= self.idx < len(self.active):
            return self.active[self.idx]
        return None

    def mark_exhausted(self, key: str, reason: str = ""):
        ex = self.state.setdefault("exhausted", [])
        if key not in ex:
            ex.append(key)
            self._save_state()
        # Убрать из активных, корректно сдвинуть индекс
        if key in self.active:
            i = self.active.index(key)
            self.active.pop(i)
            if i < self.idx:
                self.idx -= 1
            # idx сейчас уже указывает на следующий ключ (или за пределы)

    def rotate(self):
        """Перейти к следующему ключу без пометки (например на 429)."""
        self.idx += 1

    def short(self, key: str) -> str:
        return f"…{key[-6:]}" if len(key) > 6 else key

    def summary(self) -> str:
        total = len(self.all_keys)
        active = len(self.active)
        exhausted = total - active
        return (
            f"Ключей: {total}  |  активных: {active}  |  "
            f"израсходованных: {exhausted}"
        )

    @classmethod
    def classify_error(cls, exc: Exception) -> str:
        """Вернуть 'exhausted' | 'invalid' | 'ratelimit' | 'other'."""
        msg = f"{exc}".lower()
        if any(m in msg for m in cls.EXHAUST_MARKERS):
            return "exhausted"
        if any(m in msg for m in cls.INVALID_MARKERS):
            return "invalid"
        if any(m in msg for m in cls.RATELIMIT_MARKERS):
            return "ratelimit"
        return "other"


# ═══════════════════════════════════════════════════════════════════════════════
#   СБОРКА ОПИСАНИЯ ДЛЯ PIXELLAB
# ═══════════════════════════════════════════════════════════════════════════════


def build_description(state: dict) -> str:
    """
    PixelLab-friendly короткое описание. Никакой Grok-обвязки про
    'canvas 1024×1024' и зелёный фон — у PixelLab свой нативный pixel art
    с прозрачным фоном через флаг no_background.
    """
    char = CHARACTERS[state["char"]]
    dir_name, dir_desc = DIRECTIONS[state["dir"]]

    parts = [
        char["body"],
        char["outfit"],
        char["weapon"],
        char["race_features"],
        f"facing {dir_name} ({dir_desc})",
        "dark fantasy pixel art, idle relaxed pose",
    ]
    # Подсказка по палитре — у PixelLab нет прямого параметра, но в описании работает
    if char.get("palette_hint"):
        parts.append(f"color palette hint: {char['palette_hint']}")
    return ". ".join(p.strip().rstrip(".") for p in parts) + "."


# ═══════════════════════════════════════════════════════════════════════════════
#   КОНСОЛЬНЫЕ ШАГИ (специфика PixelLab)
# ═══════════════════════════════════════════════════════════════════════════════


def step_pixellab_mode() -> str | None:
    """Урезанное меню режимов: только anchor / directional."""
    cls()
    header()
    print("║" + "  ШАГ 1 / 3  —  Что генерируем?".ljust(W) + "║")
    separator()
    for i, (_, label) in enumerate(PIXELLAB_MODES, 1):
        menu_line(i, label)
    valid = {str(i) for i in range(1, len(PIXELLAB_MODES) + 1)}
    result = ask("Введи цифру", valid, allow_back=False)
    if result in ("__restart__", "__back__"):
        return None
    return PIXELLAB_MODES[int(result) - 1][0]


def load_key_manager() -> "KeyManager":
    """Создать KeyManager и упасть с понятной ошибкой, если нет активных ключей."""
    km = KeyManager()
    if not km.all_keys:
        print("⚠  Нет ни одного PixelLab API ключа.")
        print(f"   Создай файл {ENV_PATH} (смотри .env.example рядом) и впиши:")
        print("       PIXELLAB_API_KEYS=key1,key2,key3")
        print("   Либо задай переменную окружения PIXELLAB_API_KEYS.")
        sys.exit(1)
    if not km.active:
        print("⚠  Все ключи помечены как израсходованные в " f"{STATE_PATH.name}.")
        print("   Удали файл состояния или впиши новые ключи в .env.")
        sys.exit(1)
    return km


def ask_output_dir() -> Path:
    """Спросить директорию для сохранения PNG (один раз при старте)."""
    cls()
    header()
    print("║" + "  Куда сохранять PNG?".ljust(W) + "║")
    separator()
    print("║" + "  Введи путь к папке (Enter — папка по умолчанию).".ljust(W) + "║")
    print("║" + "  Папка будет создана если не существует.".ljust(W) + "║")
    footer()

    default = Path.cwd() / "_pixellab_out"
    print(f"\nПо умолчанию: {default}")
    try:
        raw = input("Папка: ").strip().strip('"').strip("'")
    except (EOFError, KeyboardInterrupt):
        sys.exit(0)
    out = Path(raw).expanduser().resolve() if raw else default
    out.mkdir(parents=True, exist_ok=True)
    print(f"  → {out}")
    return out


def ask_gen_params() -> dict:
    """Размер, no_background, кол-во вариантов, опц. стилевые параметры."""
    print("\nПараметры генерации (Enter — значение по умолчанию):")

    def _int(prompt, default):
        try:
            raw = input(f"  {prompt} [{default}]: ").strip()
        except (EOFError, KeyboardInterrupt):
            sys.exit(0)
        return int(raw) if raw.isdigit() else default

    def _yesno(prompt, default=True):
        try:
            raw = input(f"  {prompt} [{'Y/n' if default else 'y/N'}]: ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            sys.exit(0)
        if not raw:
            return default
        return raw in ("y", "yes", "д", "да")

    size = _int("Размер (px, квадрат)", 64)
    n_variants = _int("Сколько вариантов за раз (каждый = -1 генерация)", 1)
    no_bg = _yesno("Прозрачный фон (no_background)?", True)
    text_guidance = _int("text_guidance_scale (1..20, выше = строже по тексту)", 8)

    return {
        "size": max(8, min(size, 256)),
        "n": max(1, min(n_variants, 10)),
        "no_bg": no_bg,
        "text_guidance_scale": float(max(1, min(text_guidance, 20))),
    }


# ═══════════════════════════════════════════════════════════════════════════════
#   ВЫЗОВ API
# ═══════════════════════════════════════════════════════════════════════════════


def call_pixellab_with_retry(
    km: "KeyManager", description: str, params: dict, seed: int
):
    """Запрос с автоматическим переключением между ключами.
    Возвращает (PIL.Image, использованный_ключ) или (None, None) если
    все ключи исчерпаны."""
    last_err: Optional[Exception] = None

    while km.current() is not None:
        key = km.current()
        try:
            client = pixellab.Client(secret=key)
            response = client.generate_image_pixflux(
                description=description,
                image_size={"width": params["size"], "height": params["size"]},
                no_background=params["no_bg"],
                text_guidance_scale=params["text_guidance_scale"],
                seed=seed,
            )
            return response.image.pil_image(), key

        except Exception as e:
            kind = KeyManager.classify_error(e)
            last_err = e
            if kind == "exhausted":
                print(
                    f"\n    ⓘ Ключ {km.short(key)} исчерпан "
                    f"({type(e).__name__}). Помечаю в state и беру следующий."
                )
                km.mark_exhausted(key, reason=str(e)[:120])
                continue
            if kind == "invalid":
                print(
                    f"\n    ⓘ Ключ {km.short(key)} невалиден "
                    f"({type(e).__name__}). Помечаю и беру следующий."
                )
                km.mark_exhausted(key, reason=str(e)[:120])
                continue
            if kind == "ratelimit":
                print(
                    f"\n    ⓘ Rate limit на {km.short(key)}, "
                    f"переключаюсь без пометки."
                )
                km.rotate()
                continue
            # Неизвестная ошибка — пробрасываем (например, сетевая, JSON-decode)
            raise

    print(f"\n    ✗ Все активные ключи исчерпаны. " f"Последняя ошибка: {last_err}")
    return None, None


def make_filename(state: dict, seed: int, variant_idx: int) -> str:
    parts = [state["char"], state["mode"], state["dir"], f"seed{seed}"]
    if variant_idx > 0:
        parts.append(f"v{variant_idx + 1}")
    return "_".join(parts) + ".png"


def confirm_and_generate(
    km: "KeyManager", state: dict, params: dict, out_dir: Path
) -> bool:
    """Показать сводку, спросить подтверждение, дёрнуть API.
    Возвращает True если что-то сгенерировали, False если отменили."""
    description = build_description(state)

    cls()
    print("═" * (W + 2))
    print("  ОТПРАВКА В PIXELLAB")
    print("═" * (W + 2))
    print()
    print(f"  Режим:      {state['mode']}")
    print(f"  Персонаж:   {CHARACTERS[state['char']]['label']}")
    print(f"  Направление:{DIRECTIONS[state['dir']][0]}")
    print(f"  Размер:     {params['size']}×{params['size']}")
    print(f"  no_bg:      {params['no_bg']}")
    print(f"  guidance:   {params['text_guidance_scale']}")
    print(f"  Вариантов:  {params['n']}")
    print(f"  Папка:      {out_dir}")
    print()
    print("  ─── Описание для PixelLab ─────────────────────────────────")
    print(f"  {description}")
    print("  ───────────────────────────────────────────────────────────")
    print()
    try:
        raw = input("  Отправить запрос? (Y/n, b — назад в меню): ").strip().lower()
    except (EOFError, KeyboardInterrupt):
        sys.exit(0)
    if raw == "b":
        return False
    if raw == "n":
        print("  Отменено.")
        return False

    print()
    for i in range(params["n"]):
        seed = random.randint(1, 2**31 - 1)
        key_now = km.current()
        key_short = km.short(key_now) if key_now else "—"
        print(
            f"  → {i+1}/{params['n']}  seed={seed}  key={key_short}  …",
            end="",
            flush=True,
        )
        try:
            img, used_key = call_pixellab_with_retry(km, description, params, seed)
            if img is None:
                print("  (нет доступных ключей — стоп)")
                break
            out_path = out_dir / make_filename(state, seed, i)
            img.save(out_path)
            used_short = km.short(used_key) if used_key else "?"
            print(f"  ✓ {out_path.name}  (key {used_short})")
        except Exception as e:
            print(f"  ✗ {type(e).__name__}: {e}")

    try:
        input("\n  Enter — продолжить…")
    except (EOFError, KeyboardInterrupt):
        sys.exit(0)
    return True


# ═══════════════════════════════════════════════════════════════════════════════
#   ОСНОВНОЙ ЦИКЛ (state-machine, аналог run_interactive из prompt_gen)
# ═══════════════════════════════════════════════════════════════════════════════


def run():
    km = load_key_manager()
    print(f"\n  🔑 {km.summary()}")

    out_dir = ask_output_dir()
    params = ask_gen_params()

    # Проверка баланса первого активного ключа (не обязательная)
    first_key = km.current()
    if first_key:
        try:
            bal = pixellab.Client(secret=first_key).get_balance()
            print(f"\n  💰 Баланс ({km.short(first_key)}): {bal}")
        except Exception as e:
            print(f"\n  (баланс не получен: {type(e).__name__}: {e})")

    state = {"mode": None, "char": None, "dir": None}
    start_from = 1

    while True:
        # ── ШАГ 1 — Режим ────────────────────────────────────────────────────
        if start_from <= 1:
            mode = step_pixellab_mode()
            if mode is None:
                start_from = 1
                continue
            if state["mode"] != mode:
                state["char"] = None
                state["dir"] = None
            state["mode"] = mode

        # ── ШАГ 2 — Персонаж ─────────────────────────────────────────────────
        if start_from <= 2:
            char_key = step_char(_crumb(state))
            if char_key == "__restart__":
                state = {"mode": None, "char": None, "dir": None}
                start_from = 1
                continue
            if char_key == "__back__":
                start_from = 1
                continue
            state["char"] = char_key

        # ── ШАГ 3 — Направление ──────────────────────────────────────────────
        if start_from <= 3:
            exclude_s = state["mode"] == "directional"
            dir_key = step_direction(_crumb(state), exclude_south=exclude_s)
            if dir_key == "__restart__":
                state = {"mode": None, "char": None, "dir": None}
                start_from = 1
                continue
            if dir_key == "__back__":
                start_from = 2
                continue
            state["dir"] = dir_key

        # ── Подтверждение и API-запрос ───────────────────────────────────────
        if not km.active:
            print("\n  ⚠ Все ключи израсходованы — продолжать нельзя.")
            break
        confirm_and_generate(km, state, params, out_dir)

        # ── Что дальше? ──────────────────────────────────────────────────────
        cls()
        print("═" * (W + 2))
        print("  Что дальше?")
        print("─" * (W + 2))
        print("  1.  Сменить НАПРАВЛЕНИЕ  (тот же персонаж и режим)")
        print("  2.  Сменить ПЕРСОНАЖА   (тот же режим)")
        print("  3.  Сменить РЕЖИМ       (с самого начала)")
        print("  4.  Сменить ПАРАМЕТРЫ генерации (размер / варианты / no_bg)")
        print("  5.  Выйти")
        print()
        try:
            raw = input("  Введи цифру: ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            break
        if raw in ("5", "q"):
            break
        elif raw == "4":
            params = ask_gen_params()
            start_from = 1
        elif raw == "3":
            state = {"mode": None, "char": None, "dir": None}
            start_from = 1
        elif raw == "2":
            state["char"] = None
            state["dir"] = None
            start_from = 2
        elif raw == "1":
            state["dir"] = None
            start_from = 3
        else:
            start_from = 1


def main():
    try:
        run()
    except KeyboardInterrupt:
        print("\nПрервано.")
    print("Готово.")


if __name__ == "__main__":
    main()
