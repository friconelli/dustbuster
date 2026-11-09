"""Scanning and cleaning logic. No GUI imports, so it can be tested headless."""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Optional

from . import __version__

REPOSITORY = "friconelli/dustbuster"
RECENT_SECONDS = 6 * 3600


def home() -> Path:
    return Path(os.environ.get("HOME") or Path.home())


def format_bytes(n: int) -> str:
    value = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if value < 1000 or unit == "TB":
            if unit == "B":
                return f"{int(value)} B" if n else "Zero KB"
            return f"{value:.2f} {unit}".replace(".", ",") if value < 10 else f"{value:.1f} {unit}".replace(".", ",")
        value /= 1000
    return f"{n} B"


def xdg_dir(name: str, fallback: str) -> Path:
    """User folder from ~/.config/user-dirs.dirs (Scaricati, Scrivania… on an Italian system)."""
    config = home() / ".config" / "user-dirs.dirs"
    try:
        for line in config.read_text().splitlines():
            if line.startswith(f"XDG_{name}_DIR="):
                value = line.split("=", 1)[1].strip().strip('"').replace("$HOME", str(home()))
                return Path(value)
    except OSError:
        pass
    return home() / fallback


# MARK: - Git guard ---------------------------------------------------------------------------------

# Project folders: dependencies and build output are never "old files" or duplicates.
PROJECT_FOLDERS = {"node_modules", "vendor", ".venv", "venv", "__pycache__", "build", "dist", ".gradle", ".tox"}


def is_repo_root(path: Path) -> bool:
    return (Path(path) / ".git").exists()


def is_inside_repo(path: Path) -> bool:
    """True if `path` or any parent is a git repository root."""
    current = Path(path).absolute()
    while True:
        if is_repo_root(current):
            return True
        if current.parent == current:
            return False
        current = current.parent


def contains_repo(path: Path, depth: int = 3) -> bool:
    if is_repo_root(path):
        return True
    if depth <= 0:
        return False
    try:
        with os.scandir(path) as entries:
            children = [Path(e.path) for e in entries if e.is_dir(follow_symlinks=False)]
    except OSError:
        return False
    return any(contains_repo(child, depth - 1) for child in children)


# MARK: - Sizes and the Trash -----------------------------------------------------------------------

def size_of(path: Path) -> int:
    path = Path(path)
    try:
        if path.is_symlink():
            return 0
        if path.is_file():
            return os.lstat(path).st_blocks * 512
        if not path.exists():
            return 0
        out = subprocess.run(["du", "-sk", "--", str(path)], capture_output=True, text=True, timeout=900)
        return int(out.stdout.split()[0]) * 1024
    except (OSError, ValueError, IndexError, subprocess.SubprocessError):
        return 0


def _trash_fallback(path: Path) -> None:
    base = home() / ".local/share/Trash"
    (base / "files").mkdir(parents=True, exist_ok=True)
    (base / "info").mkdir(parents=True, exist_ok=True)
    name, n = path.name, 0
    while (base / "files" / name).exists():
        n += 1
        name = f"{path.name}.{n}"
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S")
    (base / "info" / f"{name}.trashinfo").write_text(
        f"[Trash Info]\nPath={path.absolute()}\nDeletionDate={stamp}\n")
    shutil.move(str(path), str(base / "files" / name))


def trash(paths: Iterable[Path]) -> list[Path]:
    """Moves to the desktop Trash (recoverable). Returns the paths that failed."""
    failed: list[Path] = []
    for p in map(Path, paths):
        try:
            try:
                import gi
                gi.require_version("Gio", "2.0")
                from gi.repository import Gio
                Gio.File.new_for_path(str(p)).trash(None)
            except (ImportError, ValueError):
                _trash_fallback(p)
        except Exception:
            failed.append(p)
    return failed


def trash_size() -> int:
    return size_of(home() / ".local/share/Trash/files")


def empty_trash() -> None:
    """The only permanent deletion in the app, always behind a confirmation."""
    base = home() / ".local/share/Trash"
    for sub in ("files", "info", "expunged"):
        folder = base / sub
        if not folder.is_dir():
            continue
        for entry in folder.iterdir():
            try:
                if entry.is_dir() and not entry.is_symlink():
                    shutil.rmtree(entry, ignore_errors=True)
                else:
                    entry.unlink()
            except OSError:
                pass


# MARK: - Categories --------------------------------------------------------------------------------

@dataclass
class Item:
    path: Path
    size: int
    modified: Optional[float] = None
    label: Optional[str] = None
    contains_repo: bool = False

    @property
    def id(self) -> str:
        return str(self.path)

    @property
    def display_name(self) -> str:
        return self.label or self.path.name

    @property
    def is_recent(self) -> bool:
        return self.modified is not None and time.time() - self.modified < RECENT_SECONDS


@dataclass
class Category:
    id: str
    title: str
    explanation: str
    safety: str                    # "safe" | "caution"
    group: str                     # "cleanup" | "ai" | "privacy"
    paths: Callable[[], list]
    lister: Optional[Callable[[Path], list]] = None
    icon: str = "folder-symbolic"
    color: str = "accent"


def _mtime(path: Path) -> Optional[float]:
    try:
        return os.lstat(path).st_mtime
    except OSError:
        return None


def child_items(base: Path, exclude: Iterable[str] = (), label_owner: bool = False) -> list[Item]:
    base = Path(base)
    items = []
    try:
        entries = sorted(base.iterdir())
    except OSError:
        return []
    for entry in entries:
        if entry.name in exclude or entry.name == ".DS_Store":
            continue
        label = f"{base.parent.name} / {base.name} / {entry.name[:24]}" if label_owner else None
        items.append(Item(entry, size_of(entry), _mtime(entry), label, contains_repo(entry) if entry.is_dir() else False))
    return sorted(items, key=lambda i: -i.size)


def claude_tmp_dir() -> Path:
    """Where Claude Code keeps its scratchpads (overridable, so tests never touch the real one)."""
    return Path(os.environ.get("DUSTBUSTER_CLAUDE_TMP") or f"/tmp/claude-{os.getuid()}")


def _claude_dirs() -> list[Path]:
    try:
        return sorted(p for p in home().iterdir() if p.name.startswith(".claude") and p.is_dir())
    except OSError:
        return []


def _claude_scratch(base: Path) -> list[Item]:
    items = []
    try:
        tops = [t for t in Path(base).iterdir() if t.is_dir()]
    except OSError:
        return []
    for top in tops:
        subs = [s for s in top.iterdir() if s.is_dir()]
        targets = subs if subs else [top]
        for target in targets:
            label = f"{top.name} / {target.name[:8]}" if subs else top.name
            items.append(Item(target, size_of(target), _mtime(target), label, contains_repo(target)))
    return sorted(items, key=lambda i: -i.size)


BACKUP_FOLDER_NAMES = {"_sostituiti", "_sostituito", "_superati", "_vecchi", "_old", "_bak", "_backup",
                       "_backups", "_replaced", "_archivio_vecchio"}
BACKUP_SUFFIXES = (".bak", ".orig", ".backup", ".old")


def is_backup_file(name: str) -> bool:
    lower = name.lower()
    # ".orig_backup" is often followed by a reason and the real extension: video.orig_backup_toodark.mp4
    return ".orig_backup" in lower or lower.endswith(BACKUP_SUFFIXES)


def walk(root: Path):
    """os.walk that never enters git repositories or dependency folders."""
    for dirpath, dirnames, filenames in os.walk(root, topdown=True, followlinks=False):
        kept = []
        for d in dirnames:
            full = Path(dirpath) / d
            if d == ".git" or d in PROJECT_FOLDERS or is_repo_root(full):
                continue
            kept.append(d)
        dirnames[:] = kept
        yield Path(dirpath), kept, filenames


def _backup_items(root: Path) -> list[Item]:
    root = Path(root)
    if not root.is_dir() or is_inside_repo(root):
        return []
    items = []
    prefix = str(home())
    for dirpath, dirnames, filenames in walk(root):
        for d in list(dirnames):
            if d.lower() in BACKUP_FOLDER_NAMES:
                dirnames.remove(d)           # listed as a whole, not opened into
                full = dirpath / d
                items.append(Item(full, size_of(full), _mtime(full), "Cartella · " + str(full).replace(prefix, "~", 1)))
        for f in filenames:
            if is_backup_file(f):
                full = dirpath / f
                try:
                    items.append(Item(full, os.lstat(full).st_blocks * 512, _mtime(full), str(full).replace(prefix, "~", 1)))
                except OSError:
                    pass
    return sorted(items, key=lambda i: -i.size)


# Browsers: (name, profile roots, process name)
BROWSERS = [
    ("Firefox", ["~/.mozilla/firefox", "~/snap/firefox/common/.mozilla/firefox", "~/.var/app/org.mozilla.firefox/.mozilla/firefox"], "firefox"),
    ("Chrome", ["~/.config/google-chrome"], "chrome"),
    ("Chromium", ["~/.config/chromium", "~/snap/chromium/common/chromium"], "chromium"),
    ("Brave", ["~/.config/BraveSoftware/Brave-Browser"], "brave"),
    ("Edge", ["~/.config/microsoft-edge"], "msedge"),
]


def _is_running(process: str) -> bool:
    return subprocess.run(["pgrep", "-x", process], capture_output=True).returncode == 0


def _browser_items(kinds: list[str]) -> list[Item]:
    items = []
    for name, roots, process in BROWSERS:
        running = _is_running(process)
        for root in roots:
            root_path = Path(root.replace("~", str(home()), 1))
            if not root_path.is_dir():
                continue
            for profile in sorted(p for p in root_path.iterdir() if p.is_dir()):
                for folder in (profile, profile / "Network"):
                    for kind in kinds:
                        f = folder / kind
                        if f.is_file():
                            suffix = " (browser aperto)" if running else ""
                            items.append(Item(f, os.lstat(f).st_blocks * 512, _mtime(f),
                                              f"{name} / {profile.name} / {kind}{suffix}"))
    return sorted(items, key=lambda i: -i.size)


def _npm_cache() -> list:
    out = None
    try:
        out = subprocess.run(["npm", "config", "get", "cache"], capture_output=True, text=True, timeout=20).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return [Path(out)] if out and Path(out).is_dir() else [home() / ".npm"]


# Folders of ~/.cache that have their own category.
_OWN_CACHES = {"thumbnails", "pip", "yarn"}


def all_categories() -> list[Category]:
    h = home()
    ai = "ai"
    return [
        Category("caches", "Cache applicazioni",
                 "Dati temporanei rigenerati automaticamente dalle app (~/.cache). Sicuro da eliminare; alcune app potrebbero essere un po' più lente al primo avvio successivo.",
                 "safe", "cleanup", lambda: [h / ".cache"], lambda p: child_items(p, _OWN_CACHES), "drive-harddisk-symbolic", "indigo"),
        Category("thumbnails", "Miniature",
                 "Anteprime di immagini e video create dal gestore file. Vengono ricreate quando servono.",
                 "safe", "cleanup", lambda: [h / ".cache/thumbnails"], None, "image-x-generic-symbolic", "plum"),
        Category("pip", "Cache pip",
                 "Pacchetti Python scaricati e conservati. Sicuro da eliminare, verranno riscaricati.",
                 "safe", "cleanup", lambda: [h / ".cache/pip"], None, "package-x-generic-symbolic", "orchid"),
        Category("yarn", "Cache Yarn",
                 "Pacchetti Yarn conservati. Sicuro da eliminare, verranno riscaricati.",
                 "safe", "cleanup", lambda: [h / ".cache/yarn"], None, "package-x-generic-symbolic", "mauve"),
        Category("npm", "Cache npm",
                 "Pacchetti npm scaricati. Vengono riscaricati quando servono. Sicuro da eliminare.",
                 "safe", "cleanup", _npm_cache, None, "package-x-generic-symbolic", "plum"),
        Category("pnpm", "Store pnpm",
                 "Store centralizzato di pnpm condiviso tra i progetti. Svuotarlo non causa perdite di dati ma rallenta le prossime installazioni.",
                 "caution", "cleanup", lambda: [h / ".local/share/pnpm/store"], None, "package-x-generic-symbolic", "mauve"),
        Category("cargo", "Cache Cargo",
                 "Pacchetti Rust scaricati (~/.cargo/registry). Vengono riscaricati al prossimo build.",
                 "safe", "cleanup", lambda: [h / ".cargo/registry/cache"], None, "package-x-generic-symbolic", "indigo"),
        # --- AI tools ---
        Category("claude-scratch", "Claude · lavoro",
                 "Cartelle scratchpad temporanee create da Claude Code durante le sessioni passate (file scaricati, estratti, output intermedi). Sicure da eliminare, tranne quelle modificate di recente che potrebbero essere ancora in corso.",
                 "safe", ai, lambda: [claude_tmp_dir()], _claude_scratch, "weather-clear-symbolic", "orchid"),
        Category("claude-edit-backups", "Claude · pre-modifica",
                 "Prima di ogni modifica Claude Code salva una copia del file (file-history), usata solo per annullare le modifiche di una sessione. Eliminarle non tocca i tuoi progetti.",
                 "safe", ai, lambda: [d / "file-history" for d in _claude_dirs()], lambda p: child_items(p, label_owner=True),
                 "document-open-recent-symbolic", "plum"),
        Category("claude-temp", "Claude · temporanei",
                 "Snapshot della shell, testi incollati, ambienti di sessione, telemetria, log di debug e copie di sicurezza della configurazione. Le conversazioni (cartella projects) non vengono mai toccate.",
                 "safe", ai, lambda: [d / n for d in _claude_dirs() for n in ("shell-snapshots", "paste-cache", "session-env", "telemetry", "debug", "backups")],
                 lambda p: child_items(p, label_owner=True), "view-refresh-symbolic", "mauve"),
        Category("codex-temp", "Codex · cache",
                 "Cache dei plugin, snapshot della shell e file temporanei di Codex. Cronologia e sessioni non sono incluse.",
                 "safe", ai, lambda: [h / ".codex" / n for n in ("cache", "tmp", "shell_snapshots")], lambda p: child_items(p, label_owner=True),
                 "utilities-terminal-symbolic", "indigo"),
        Category("codex-images", "Codex · immagini",
                 "Immagini create da Codex. Se non le hai salvate altrove, eliminandole le perdi: controlla prima.",
                 "caution", ai, lambda: [h / ".codex/generated_images"], lambda p: child_items(p, label_owner=True),
                 "camera-photo-symbolic", "night"),
        Category("ai-backup-files", "Backup lasciati dall'AI",
                 "Copie di sicurezza che l'AI mette da parte prima di modificare un file: cartelle come _sostituiti o _backup (mostrate per intero) e file come .orig_backup, .bak, .orig, .backup in Scrivania, Documenti, Download, Video e progetti. Controlla che la modifica sia andata a buon fine prima di eliminarle. I file dentro repository git non vengono mai mostrati e nessuna voce è preselezionata.",
                 "caution", ai,
                 lambda: [xdg_dir("DESKTOP", "Desktop"), xdg_dir("DOCUMENTS", "Documents"), xdg_dir("DOWNLOAD", "Downloads"),
                          xdg_dir("VIDEOS", "Videos"), h / "projects"],
                 _backup_items, "emblem-documents-symbolic", "slate"),
        # --- Privacy ---
        Category("browser-history", "Cronologia dei browser",
                 "Pagine visitate, siti più visitati e dati di navigazione di Firefox, Chrome, Chromium, Brave ed Edge. Chiudi il browser prima di eliminare. Perdi la cronologia ma non i segnalibri né le password.",
                 "caution", "privacy", lambda: [h],
                 lambda _p: _browser_items(["History", "Top Sites", "Visited Links", "Favicons", "places.sqlite", "favicons.sqlite"]),
                 "document-open-recent-symbolic", "indigo"),
        Category("browser-cookies", "Cookie dei browser",
                 "Cookie di Firefox, Chrome, Chromium, Brave ed Edge. Eliminandoli esci da tutti i siti in cui sei collegato e dovrai rifare l'accesso. Chiudi il browser prima di procedere.",
                 "caution", "privacy", lambda: [h],
                 lambda _p: _browser_items(["Cookies", "Cookies-journal", "cookies.sqlite"]),
                 "changes-prevent-symbolic", "indigo"),
    ]


def scan_category(category: Category) -> list[Item]:
    found: list[Item] = []
    for path in category.paths():
        if not Path(path).exists():
            continue
        found += category.lister(Path(path)) if category.lister else child_items(Path(path))
    return sorted(found, key=lambda i: -i.size)


def smart_clean_items(items_by_category: dict, categories: list[Category]) -> list[Item]:
    """Everything safe to remove in one go: 'safe' categories, nothing recent, nothing in a repository."""
    seen: set = set()
    result = []
    for c in categories:
        if c.safety != "safe":
            continue
        for item in items_by_category.get(c.id, []):
            if item.is_recent or item.contains_repo or is_inside_repo(item.path) or item.id in seen:
                continue
            seen.add(item.id)
            result.append(item)
    return result


# MARK: - Duplicates --------------------------------------------------------------------------------

@dataclass
class DupFile:
    path: Path
    size: int
    modified: float


@dataclass
class DupGroup:
    files: list

    @property
    def wasted(self) -> int:
        return self.files[0].size * (len(self.files) - 1) if len(self.files) > 1 else 0


def _hash(path: Path, limit: Optional[int] = None) -> Optional[str]:
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            remaining = limit
            while True:
                chunk = f.read(1024 * 1024 if remaining is None else min(1024 * 1024, remaining))
                if not chunk:
                    break
                h.update(chunk)
                if remaining is not None:
                    remaining -= len(chunk)
                    if remaining <= 0:
                        break
    except OSError:
        return None
    return h.hexdigest()


def default_duplicate_folders() -> list[Path]:
    return [p for p in (xdg_dir("DOWNLOAD", "Downloads"), xdg_dir("DESKTOP", "Desktop"), xdg_dir("DOCUMENTS", "Documents")) if p.is_dir()]


def find_duplicates(folders: list, progress: Callable[[str], None] = lambda _n: None) -> list[DupGroup]:
    by_size: dict = {}
    for folder in map(Path, folders):
        if is_inside_repo(folder):
            continue                        # a folder chosen from inside a repository is skipped
        for dirpath, dirnames, filenames in walk(folder):
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
            for name in filenames:
                if name.startswith("."):
                    continue
                full = dirpath / name
                try:
                    st = os.lstat(full)
                except OSError:
                    continue
                if not os.path.isfile(full) or os.path.islink(full) or st.st_size <= 4096:
                    continue
                by_size.setdefault(st.st_size, []).append((full, st))
    groups = []
    for size, entries in by_size.items():
        if len(entries) < 2:
            continue
        by_head: dict = {}
        for full, st in entries:
            progress(full.name)
            head = _hash(full, 65536)
            if head:
                by_head.setdefault(head, []).append((full, st))
        for candidates in by_head.values():
            if len(candidates) < 2:
                continue
            by_full: dict = {}
            for full, st in candidates:
                digest = _hash(full)
                if digest:
                    by_full.setdefault(digest, []).append((full, st))
            for same in by_full.values():
                if len(same) > 1:
                    files = sorted((DupFile(f, st.st_size, st.st_mtime) for f, st in same), key=lambda x: x.modified)
                    groups.append(DupGroup(files))
    return sorted(groups, key=lambda g: -g.wasted)


# MARK: - Large and old files -----------------------------------------------------------------------

@dataclass
class LargeFile:
    path: Path
    size: int
    last_touched: float


def large_file_roots() -> list[Path]:
    names = [("DOWNLOAD", "Downloads"), ("DESKTOP", "Desktop"), ("DOCUMENTS", "Documents"),
             ("VIDEOS", "Videos"), ("MUSIC", "Music"), ("PICTURES", "Pictures")]
    return [p for p in (xdg_dir(n, f) for n, f in names) if p.is_dir()]


def find_large_files(roots: list, min_bytes: int, older_than: Optional[float]) -> list[LargeFile]:
    found = []
    for root in map(Path, roots):
        if is_inside_repo(root):
            continue
        for dirpath, _dirs, filenames in walk(root):
            for name in filenames:
                full = dirpath / name
                try:
                    st = os.lstat(full)
                except OSError:
                    continue
                if not os.path.isfile(full) or os.path.islink(full):
                    continue
                size = st.st_blocks * 512
                if size < min_bytes:
                    continue
                touched = max(st.st_atime, st.st_mtime)
                if older_than is not None and touched > older_than:
                    continue
                found.append(LargeFile(full, size, touched))
    return sorted(found, key=lambda f: -f.size)


# MARK: - Disk map ----------------------------------------------------------------------------------

@dataclass
class MapNode:
    path: Path
    size: int
    is_dir: bool
    protected: bool          # in or containing a git repository: shown, never selectable


def scan_children(folder: Path, on_node: Callable[[MapNode], None]) -> None:
    """Measures the direct children in parallel, reporting each as soon as it is done."""
    from concurrent.futures import ThreadPoolExecutor
    folder = Path(folder)
    parent_in_repo = is_inside_repo(folder)
    try:
        children = [c for c in folder.iterdir() if not c.is_symlink()]
    except OSError:
        return

    def measure(child: Path):
        is_dir = child.is_dir()
        size = size_of(child)
        if size <= 0:
            return
        on_node(MapNode(child, size, is_dir, parent_in_repo or (is_dir and contains_repo(child, 2))))

    with ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(measure, children))


def squarify(values: list, x: float, y: float, w: float, h: float) -> list:
    """Squarified treemap: rectangles (x, y, w, h) for values sorted descending."""
    total = float(sum(values))
    if total <= 0 or w <= 0 or h <= 0:
        return [(0, 0, 0, 0)] * len(values)
    scale = w * h / total
    areas = [v * scale for v in values]
    rects = [(0.0, 0.0, 0.0, 0.0)] * len(areas)

    def worst(row, side):
        s = sum(row)
        if s <= 0 or min(row) <= 0:
            return float("inf")
        return max(side * side * max(row) / (s * s), s * s / (side * side * min(row)))

    rx, ry, rw, rh = x, y, w, h
    start = 0
    while start < len(areas):
        side = min(rw, rh)
        end = start + 1
        while end < len(areas) and worst(areas[start:end + 1], side) <= worst(areas[start:end], side):
            end += 1
        row = areas[start:end]
        s = sum(row)
        if rw >= rh:
            width = s / rh
            cy = ry
            for i in range(start, end):
                height = areas[i] / width
                rects[i] = (rx, cy, width, height)
                cy += height
            rx, rw = rx + width, rw - width
        else:
            height = s / rw
            cx = rx
            for i in range(start, end):
                width = areas[i] / height
                rects[i] = (cx, ry, width, height)
                cx += width
            ry, rh = ry + height, rh - height
        start = end
    return rects


# MARK: - Startup items -----------------------------------------------------------------------------

@dataclass
class StartupItem:
    path: Path
    name: str
    exec_line: str
    scope: str               # "user" | "system"
    enabled: bool
    program_missing: bool

    @property
    def id(self) -> str:
        return str(self.path)


def _parse_desktop(path: Path) -> dict:
    data: dict = {}
    in_entry = False
    try:
        for line in path.read_text(errors="replace").splitlines():
            line = line.strip()
            if line.startswith("["):
                in_entry = line == "[Desktop Entry]"
            elif in_entry and "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                data.setdefault(k.strip(), v.strip())
    except OSError:
        pass
    return data


def autostart_dirs() -> tuple:
    config = Path(os.environ.get("XDG_CONFIG_HOME") or home() / ".config")
    return config / "autostart", Path("/etc/xdg/autostart")


def scan_startup() -> list[StartupItem]:
    user_dir, system_dir = autostart_dirs()
    seen: set = set()
    items = []
    for folder, scope in ((user_dir, "user"), (system_dir, "system")):
        if not folder.is_dir():
            continue
        for f in sorted(folder.glob("*.desktop")):
            if f.name in seen:
                continue                      # a user file overrides the system one with the same name
            seen.add(f.name)
            d = _parse_desktop(f)
            exec_line = d.get("Exec", "")
            program = exec_line.split()[0] if exec_line.split() else ""
            enabled = d.get("Hidden", "false").lower() != "true" and d.get("X-GNOME-Autostart-enabled", "true").lower() != "false"
            missing = bool(program) and shutil.which(program) is None and not (program.startswith("/") and os.path.exists(program))
            items.append(StartupItem(f, d.get("Name", f.stem), exec_line, scope, enabled, missing))
    return sorted(items, key=lambda i: (not i.program_missing, i.name.lower()))


def set_startup_enabled(item: StartupItem, enabled: bool) -> None:
    """Reversible: writes X-GNOME-Autostart-enabled in the user's autostart folder (never deletes anything)."""
    user_dir, _ = autostart_dirs()
    user_dir.mkdir(parents=True, exist_ok=True)
    target = user_dir / item.path.name
    text = item.path.read_text(errors="replace")
    lines = [ln for ln in text.splitlines() if not ln.startswith("X-GNOME-Autostart-enabled=") and not ln.startswith("Hidden=")]
    out, inserted = [], False
    for ln in lines:
        out.append(ln)
        if ln.strip() == "[Desktop Entry]" and not inserted:
            out.append(f"X-GNOME-Autostart-enabled={'true' if enabled else 'false'}")
            inserted = True
    target.write_text("\n".join(out) + "\n")


# MARK: - Updates -----------------------------------------------------------------------------------

def is_newer(candidate: str, current: str) -> bool:
    def parts(v):
        return [int(x) if x.isdigit() else 0 for x in re.split(r"[.\-]", v.lstrip("vV"))]
    a, b = parts(candidate), parts(current)
    for i in range(max(len(a), len(b))):
        x = a[i] if i < len(a) else 0
        y = b[i] if i < len(b) else 0
        if x != y:
            return x > y
    return False


@dataclass
class Release:
    version: str
    notes: str
    deb_url: str
    page_url: str


def latest_release(repository: Optional[str] = None) -> Optional[Release]:
    """The newest GitHub release that carries a .deb, or None when there is none yet."""
    repo = repository or os.environ.get("DUSTBUSTER_UPDATE_REPO", REPOSITORY)
    req = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/latest",
                                 headers={"Accept": "application/vnd.github+json", "User-Agent": "dustbuster-linux"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            payload = json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise
    asset = next((a for a in payload.get("assets", []) if re.fullmatch(r"dustbuster_.+_all\.deb", a["name"])), None)
    if asset is None:
        raise RuntimeError(f"La release {payload.get('tag_name')} non contiene il pacchetto .deb per Linux")
    return Release(payload["tag_name"].lstrip("vV"), payload.get("body") or "", asset["browser_download_url"], payload["html_url"])


def download_update(release: Release, dest_dir: Path) -> Path:
    dest = Path(dest_dir) / f"dustbuster_{release.version}_all.deb"
    req = urllib.request.Request(release.deb_url, headers={"User-Agent": "dustbuster-linux"})
    with urllib.request.urlopen(req, timeout=120) as r, open(dest, "wb") as f:
        shutil.copyfileobj(r, f)
    return dest


def verify_deb(path: Path, expected_version: str) -> None:
    """Refuses a package that is not Dustbuster at the expected version."""
    out = subprocess.run(["dpkg-deb", "-f", str(path), "Package", "Version"], capture_output=True, text=True)
    fields = dict(line.split(": ", 1) for line in out.stdout.splitlines() if ": " in line)
    if out.returncode != 0 or fields.get("Package") != "dustbuster" or fields.get("Version") != expected_version:
        raise RuntimeError("Il pacchetto scaricato non è una versione valida di Dustbuster.")


def install_deb(path: Path) -> None:
    """Installs with administrator rights through polkit (the system asks for the password)."""
    cmd = ["pkexec", "apt-get", "install", "-y", "--allow-downgrades", str(path)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout or "installazione non riuscita").strip().splitlines()[-1])
