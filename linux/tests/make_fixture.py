"""Builds a throw-away home folder with realistic clutter, for trying the app and taking screenshots.
Usage: python3 tests/make_fixture.py /tmp/fakehome   (then run with HOME=/tmp/fakehome)"""
import os
import sys
import time
from pathlib import Path

home = Path(sys.argv[1])
scratch = home / "claude-tmp"


def w(path, size, age_days=30):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(os.urandom(1024) * (size // 1024))
    t = time.time() - age_days * 86400
    os.utime(p, (t, t))
    return p


def age(path, days):
    t = time.time() - days * 86400
    os.utime(path, (t, t))


blob = os.urandom(1024) * 3000
for d in ("Documenti/foto", "Documenti/copie", "Scrivania"):
    (home / d).mkdir(parents=True, exist_ok=True)
for p in ("Documenti/foto/vacanza.jpg", "Documenti/copie/vacanza (copia).jpg", "Scrivania/vacanza.jpg"):
    (home / p).write_bytes(blob)
(home / "Documenti/progetto/.git").mkdir(parents=True)
(home / "Documenti/progetto/vacanza.jpg").write_bytes(blob)       # a repo copy: must never be offered
w(home / ".cache/mozilla/cache2/entries.bin", 180_000_000, 20)
w(home / ".cache/google-chrome/Default/Cache/data_1", 90_000_000, 12)
w(home / ".cache/thumbnails/large/a.png", 30_000_000, 40)
w(home / ".cache/pip/http/abc", 40_000_000, 60)
w(home / ".npm/_cacache/content/x", 70_000_000, 25)
w(home / ".claude/file-history/s1/v1", 40_000_000, 50)
w(home / ".claude-work/telemetry/t.json", 3_000_000, 50)
w(scratch / "-progetti/sess-aaaa/out.bin", 120_000_000, 9)
w(scratch / "-progetti/sess-bbbb/out.bin", 60_000_000, 7)
age(scratch / "-progetti/sess-aaaa", 9)
age(scratch / "-progetti/sess-bbbb", 7)
w(home / ".codex/cache/c.bin", 25_000_000, 30)
w(home / "Scrivania/Lavori/_sostituiti/Carousel (prima del logo).ai", 90_000_000, 20)
w(home / "Scrivania/Lavori/_sostituiti/Poster (colori v1).ai", 60_000_000, 20)
w(home / "Scrivania/video-post.orig_backup_toodark.mp4", 14_000_000, 25)
w(home / "Documenti/note.txt.bak", 1_000_000, 90)
w(home / "Video/film-2019.mkv", 900_000_000, 500)
w(home / "Scaricati/ubuntu.iso", 600_000_000, 300)
w(home / ".mozilla/firefox/abc.default/places.sqlite", 24_000_000, 1)
w(home / ".mozilla/firefox/abc.default/cookies.sqlite", 3_000_000, 1)
w(home / ".config/google-chrome/Default/History", 9_000_000, 1)
(home / ".config/autostart").mkdir(parents=True, exist_ok=True)
(home / ".config/autostart/ghost.desktop").write_text("[Desktop Entry]\nType=Application\nName=Vecchio updater\nExec=old-updater --silent\n")
(home / ".config/autostart/syncthing.desktop").write_text("[Desktop Entry]\nType=Application\nName=Syncthing\nExec=sh -c true\n")
(home / ".config").mkdir(exist_ok=True)
(home / ".config/user-dirs.dirs").write_text(
    'XDG_DESKTOP_DIR="$HOME/Scrivania"\nXDG_DOWNLOAD_DIR="$HOME/Scaricati"\nXDG_DOCUMENTS_DIR="$HOME/Documenti"\nXDG_VIDEOS_DIR="$HOME/Video"\n')
t = home / ".local/share/Trash/files"
t.mkdir(parents=True, exist_ok=True)
w(t / "vecchio-cestino.bin", 50_000_000, 5)
print("fixture ready:", home, "| claude tmp:", scratch)
