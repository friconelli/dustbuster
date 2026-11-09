import os
import shutil
import tempfile
import time
import unittest
from pathlib import Path

# Everything the tests create lives in one temporary folder, which is the only thing they remove.
SANDBOX = Path(tempfile.mkdtemp(prefix="dustbuster-test-"))
HOME = str(SANDBOX / "home")
os.makedirs(HOME)
os.environ["HOME"] = HOME
os.environ["DUSTBUSTER_CLAUDE_TMP"] = str(SANDBOX / "claude-tmp")
os.environ.pop("XDG_CONFIG_HOME", None)

from dustbuster import core  # noqa: E402


def write(path, data=b"x" * 20000, age_hours=100):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    t = time.time() - age_hours * 3600
    os.utime(path, (t, t))
    return path


class CoreTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        h = Path(HOME)
        scratch = Path(os.environ["DUSTBUSTER_CLAUDE_TMP"])
        blob = os.urandom(20000)
        # duplicates: two loose copies, one in a git repo, one in node_modules
        write(h / "Documents/loose/d.bin", blob)
        write(h / "Documents/loose/e.bin", blob, age_hours=10)
        write(h / "Documents/proj/a.bin", blob)
        (h / "Documents/proj/.git").mkdir(parents=True)
        write(h / "Documents/proj/node_modules/x/c.bin", blob)
        # backups
        write(h / "Desktop/Lavori/_sostituiti/old.ai", b"o" * 50000)
        write(h / "Desktop/video-post.orig_backup_toodark.mp4", b"v" * 30000)
        write(h / "Desktop/notes.txt.bak", b"b" * 1000)
        write(h / "Desktop/repo2/_backup/keep.txt", b"k" * 1000)
        (h / "Desktop/repo2/.git").mkdir(parents=True)
        # caches and AI temp files
        write(h / ".cache/foo/f.bin", b"c" * 100000)
        write(h / ".cache/thumbnails/normal/t.png", b"t" * 5000)
        write(h / ".claude/file-history/abc/v1", b"h" * 5000)
        write(h / ".claude-work/shell-snapshots/s.sh", b"s" * 5000)
        write(scratch / "-proj/sess-old/out.txt", b"o" * 5000, age_hours=100)
        write(scratch / "-proj/sess-new/out.txt", b"n" * 5000, age_hours=0)
        old = time.time() - 360000
        for d in (scratch / "-proj/sess-old", h / ".cache/foo"):
            os.utime(d, (old, old))          # a folder's own mtime changes when it is created
        # browsers
        write(h / ".mozilla/firefox/abc.default/places.sqlite", b"p" * 8000)
        write(h / ".mozilla/firefox/abc.default/cookies.sqlite", b"q" * 8000)
        # startup
        write(h / ".config/autostart/ghost.desktop",
              b"[Desktop Entry]\nType=Application\nName=Ghost\nExec=definitely-not-installed --x\n")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(SANDBOX, ignore_errors=True)

    def test_git_guard(self):
        h = Path(HOME)
        self.assertTrue(core.is_inside_repo(h / "Documents/proj/a.bin"))
        self.assertFalse(core.is_inside_repo(h / "Documents/loose/d.bin"))
        self.assertTrue(core.contains_repo(h / "Documents"))

    def test_duplicates_ignore_repos_and_dependencies(self):
        groups = core.find_duplicates([Path(HOME) / "Documents"])
        self.assertEqual(len(groups), 1)
        names = sorted(f.path.name for f in groups[0].files)
        self.assertEqual(names, ["d.bin", "e.bin"])
        self.assertEqual(groups[0].files[0].path.name, "d.bin")          # oldest first (kept)
        self.assertEqual(core.find_duplicates([Path(HOME) / "Documents/proj"]), [])

    def test_backups_found_but_not_inside_repos(self):
        cat = next(c for c in core.all_categories() if c.id == "ai-backup-files")
        paths = {i.path.name for i in core.scan_category(cat)}
        self.assertIn("_sostituiti", paths)
        self.assertIn("video-post.orig_backup_toodark.mp4", paths)
        self.assertIn("notes.txt.bak", paths)
        self.assertNotIn("_backup", paths)
        self.assertNotIn("keep.txt", paths)

    def test_ai_and_cache_categories(self):
        by_id = {c.id: core.scan_category(c) for c in core.all_categories()}
        self.assertTrue(any(i.path.name == "foo" for i in by_id["caches"]))
        self.assertFalse(any(i.path.name == "thumbnails" for i in by_id["caches"]))
        self.assertTrue(by_id["claude-edit-backups"])
        self.assertTrue(by_id["claude-temp"])
        self.assertEqual(len(by_id["browser-history"]), 1)
        self.assertEqual(len(by_id["browser-cookies"]), 1)
        scratch = {i.path.name: i for i in by_id["claude-scratch"]}
        self.assertFalse(scratch["sess-old"].is_recent)
        self.assertTrue(scratch["sess-new"].is_recent)

    def test_smart_clean_is_conservative(self):
        cats = core.all_categories()
        items = {c.id: core.scan_category(c) for c in cats}
        names = {i.path.name for i in core.smart_clean_items(items, cats)}
        self.assertIn("foo", names)
        self.assertIn("sess-old", names)
        self.assertNotIn("sess-new", names)                  # recent
        self.assertNotIn("_sostituiti", names)               # caution category
        self.assertNotIn("places.sqlite", names)             # privacy is caution

    def test_trash_is_recoverable(self):
        f = write(Path(HOME) / "Desktop/to-trash.txt", b"z" * 100)
        self.assertEqual(core.trash([f]), [])
        self.assertFalse(f.exists())
        self.assertEqual(len(list((Path(HOME) / ".local/share/Trash/files").glob("to-trash*"))), 1)
        infos = list((Path(HOME) / ".local/share/Trash/info").glob("to-trash*.trashinfo"))
        self.assertEqual(len(infos), 1)
        self.assertIn("Path=", infos[0].read_text())
        core.empty_trash()
        self.assertEqual(list((Path(HOME) / ".local/share/Trash/files").glob("*")), [])

    def test_large_files(self):
        h = Path(HOME)
        write(h / "Downloads/big.iso", b"i" * 3_000_000, age_hours=24 * 400)
        write(h / "Downloads/fresh.iso", b"i" * 3_000_000, age_hours=1)
        write(h / "Downloads/repo/.git/HEAD", b"ref")
        write(h / "Downloads/repo/huge.bin", b"h" * 3_000_000, age_hours=24 * 400)
        found = core.find_large_files([h / "Downloads"], 1_000_000, time.time() - 180 * 86400)
        self.assertEqual([f.path.name for f in found], ["big.iso"])

    def test_startup_toggle(self):
        ghost = next(i for i in core.scan_startup() if i.name == "Ghost")
        self.assertTrue(ghost.program_missing)
        self.assertTrue(ghost.enabled)
        core.set_startup_enabled(ghost, False)
        ghost2 = next(i for i in core.scan_startup() if i.name == "Ghost")
        self.assertFalse(ghost2.enabled)
        core.set_startup_enabled(ghost2, True)
        self.assertTrue(next(i for i in core.scan_startup() if i.name == "Ghost").enabled)

    def test_squarify_fills_the_area(self):
        rects = core.squarify([600, 300, 200, 100, 50], 0, 0, 400, 300)
        self.assertAlmostEqual(sum(w * h for _x, _y, w, h in rects), 400 * 300, delta=1)
        for x, y, w, h in rects:
            self.assertGreaterEqual(x, -0.01)
            self.assertLessEqual(x + w, 400.01)
            self.assertLessEqual(y + h, 300.01)

    def test_misc(self):
        self.assertTrue(core.is_newer("1.10.0", "1.9.3"))
        self.assertFalse(core.is_newer("1.0", "1.0.0"))
        self.assertFalse(core.is_newer("1.0.0", "1.1.0"))
        self.assertEqual(core.format_bytes(0), "Zero KB")
        self.assertEqual(core.format_bytes(2_500_000_000), "2,50 GB")


if __name__ == "__main__":
    unittest.main()
