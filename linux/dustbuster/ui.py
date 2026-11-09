"""GTK 3 interface for Dustbuster (Zorin OS / GNOME). Works on GTK 3.24 + Python 3.10."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk, Pango  # noqa: E402

from . import __version__, core  # noqa: E402

APP_ID = "com.federicomancinelli.dustbuster"

COLORS = {
    "accent": "#FE57A6", "accentdeep": "#C2185F", "ink": "#241358", "night": "#33266B", "plum": "#8C3399",
    "indigo": "#4540B8", "orchid": "#CC4DB3", "slate": "#5C6180", "mauve": "#8066B8",
}

CSS = """
.hero { background-image: linear-gradient(135deg, #381F80, #241358); border-radius: 20px; padding: 26px; color: white; }
.hero label { color: white; }
.hero .hero-total { font-size: 46px; font-weight: 800; color: #FE57A6; }
.hero .hero-sub { color: alpha(white, 0.8); }
.ai-banner { background-image: linear-gradient(90deg, #FE57A6, #8F45DB); border-radius: 16px; padding: 16px 20px; }
.ai-banner label { color: white; }
.card { background-color: @theme_base_color; border-radius: 14px; border: 1px solid alpha(currentColor, 0.09); padding: 14px; }
button.card-button { background-image: none; padding: 0; border-radius: 14px; border: 1px solid alpha(currentColor, 0.09); }
button.card-button:hover { background-color: alpha(#FE57A6, 0.08); }
.tile { border-radius: 9px; color: white; }
%(tiles)s
.badge { border-radius: 999px; padding: 1px 9px; font-size: 11px; font-weight: 600; }
.badge-safe { background-color: alpha(#2E9E5B, 0.16); color: #1F7A42; }
.badge-caution { background-color: alpha(#F08A24, 0.16); color: #B8620D; }
.badge-repo { background-color: alpha(#D32F2F, 0.14); color: #C62828; }
.badge-warn { background-color: alpha(#F08A24, 0.16); color: #B8620D; }
.page-title { font-size: 22px; font-weight: 800; }
.section-title { font-size: 17px; font-weight: 700; }
.big-size { font-size: 22px; font-weight: 800; }
.dim { color: alpha(currentColor, 0.62); }
.faint { color: alpha(currentColor, 0.45); font-size: 11px; }
button.accent { background-image: none; background-color: #C2185F; color: white; border-radius: 9px; border: none; text-shadow: none; }
button.accent:hover { background-color: #D81B7E; }
button.accent:disabled { background-color: alpha(#C2185F, 0.35); }
button.danger { background-image: none; background-color: #D32F2F; color: white; border-radius: 9px; border: none; text-shadow: none; }
button.danger:disabled { background-color: alpha(#D32F2F, 0.35); }
button.on-hero { background-image: none; background-color: #FE57A6; color: #241358; border-radius: 9px; border: none; font-weight: 700; }
button.on-hero-ghost { background-image: none; background-color: alpha(white, 0.14); color: white; border-radius: 9px; border: none; }
progressbar.thin trough, progressbar.thin progress { min-height: 4px; border-radius: 4px; }
progressbar.thin progress { background-color: #C2185F; background-image: none; }
.sidebar { background-color: alpha(currentColor, 0.035); }
.sidebar row { padding: 2px 6px; border-radius: 9px; }
.sidebar row:selected { background-color: alpha(#C2185F, 0.14); color: inherit; }
.sidebar .group-title { font-size: 11px; font-weight: 700; color: alpha(currentColor, 0.5); }
.update-box { background-color: alpha(#FE57A6, 0.15); border-radius: 10px; padding: 10px; }
actionbar { border-radius: 14px; }
check:checked, radio:checked { background-image: none; background-color: #C2185F; border-color: #C2185F; color: white; }
switch:checked { background-image: none; background-color: #C2185F; border-color: #C2185F; }
switch:checked slider { border-color: #C2185F; }
"""


def build_css() -> str:
    tiles = "\n".join(
        f".tile-{k} {{ background-image: linear-gradient({v}, shade({v}, 0.82)); }}" for k, v in COLORS.items())
    return CSS % {"tiles": tiles}


def clear(box) -> None:
    for child in box.get_children():
        box.remove(child)


def label(text: str, css: str = "", wrap: bool = False, xalign: float = 0.0, ellipsize: bool = False, selectable: bool = False):
    lab = Gtk.Label(label=text, xalign=xalign)
    for c in css.split():
        lab.get_style_context().add_class(c)
    if wrap:
        lab.set_line_wrap(True)
        lab.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
        lab.set_max_width_chars(80)
    if ellipsize:
        lab.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
    lab.set_selectable(selectable)
    return lab


def tile(icon: str, color: str, size: int = 36) -> Gtk.Widget:
    box = Gtk.Box()
    box.get_style_context().add_class("tile")
    box.get_style_context().add_class(f"tile-{color}")
    box.set_size_request(size, size)
    img = Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.LARGE_TOOLBAR)
    img.set_pixel_size(int(size * 0.5))
    box.set_center_widget(img)
    box.set_valign(Gtk.Align.CENTER)
    return box


def badge(text: str, kind: str, tooltip: str = "") -> Gtk.Widget:
    lab = Gtk.Label(label=text)
    for c in ("badge", f"badge-{kind}"):
        lab.get_style_context().add_class(c)
    lab.set_valign(Gtk.Align.CENTER)
    if tooltip:
        lab.set_tooltip_text(tooltip)
    return lab


def relative(ts: float | None) -> str:
    if not ts:
        return ""
    delta = max(0, time.time() - ts)
    if delta < 60:
        return "ora"
    for limit, div, one, many in ((3600, 60, "min", "min"), (86400, 3600, "h", "h"), (86400 * 30, 86400, "giorno", "giorni"),
                                  (86400 * 365, 86400 * 30, "mese", "mesi")):
        if delta < limit:
            n = int(delta // div)
            return f"{n} {one if n == 1 else many} fa"
    n = int(delta // (86400 * 365))
    return f"{n} {'anno' if n == 1 else 'anni'} fa"


def button(text: str, css: str = "", icon: str | None = None) -> Gtk.Button:
    b = Gtk.Button()
    box = Gtk.Box(spacing=6)
    if icon:
        box.pack_start(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.BUTTON), False, False, 0)
    box.pack_start(Gtk.Label(label=text), False, False, 0)
    b.add(box)
    for c in css.split():
        b.get_style_context().add_class(c)
    return b


def confirm(parent, title: str, text: str, ok: str = "Sposta nel Cestino", destructive: bool = True) -> bool:
    dialog = Gtk.MessageDialog(transient_for=parent, modal=True, message_type=Gtk.MessageType.WARNING,
                               text=title, secondary_text=text)
    dialog.add_button("Annulla", Gtk.ResponseType.CANCEL)
    btn = dialog.add_button(ok, Gtk.ResponseType.OK)
    if destructive:
        btn.get_style_context().add_class("destructive-action")
    response = dialog.run()
    dialog.destroy()
    return response == Gtk.ResponseType.OK


def info(parent, title: str, text: str = "") -> None:
    dialog = Gtk.MessageDialog(transient_for=parent, modal=True, message_type=Gtk.MessageType.INFO,
                               buttons=Gtk.ButtonsType.OK, text=title, secondary_text=text)
    dialog.run()
    dialog.destroy()


def open_folder(path: Path) -> None:
    target = path if path.is_dir() else path.parent
    subprocess.Popen(["xdg-open", str(target)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def background(work, done) -> None:
    """Runs `work()` in a thread and calls `done(result)` on the GTK main loop."""
    def run():
        try:
            result = work()
        except Exception as e:  # noqa: BLE001
            result = e
        GLib.idle_add(done, result)
    threading.Thread(target=run, daemon=True).start()


class ActionBar(Gtk.ActionBar):
    """Bottom bar shown while something is selected."""

    def __init__(self, on_clear, on_trash):
        super().__init__()
        self.info = label("", "dim")
        self.pack_start(self.info)
        self.trash_button = button("Sposta nel Cestino", "danger", "user-trash-symbolic")
        self.trash_button.connect("clicked", lambda _b: on_trash())
        clear_button = button("Deseleziona")
        clear_button.connect("clicked", lambda _b: on_clear())
        self.pack_end(self.trash_button)
        self.pack_end(clear_button)

    def update(self, count: int, size: int) -> None:
        self.info.set_text(f"{count} selezionati · {core.format_bytes(size)}")
        self.set_visible(count > 0)
        self.set_no_show_all(False)
        if count > 0:
            self.show_all()


def item_row(name: str, size: int, selected: bool, on_toggle, largest: int, subtitle: str = "", when: str = "",
             badges: list | None = None, folder: Path | None = None, checkable: bool = True) -> Gtk.ListBoxRow:
    row = Gtk.ListBoxRow()
    row.set_activatable(False)
    outer = Gtk.Box(spacing=12, margin=8)
    check = Gtk.CheckButton()
    check.set_active(selected)
    check.set_sensitive(checkable)
    check.connect("toggled", lambda c: on_toggle(c.get_active()))
    outer.pack_start(check, False, False, 0)
    middle = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
    top = Gtk.Box(spacing=6)
    top.pack_start(label(name, ellipsize=True), False, False, 0)
    for b in badges or []:
        top.pack_start(b, False, False, 0)
    middle.pack_start(top, False, False, 0)
    if subtitle:
        middle.pack_start(label(subtitle, "faint", ellipsize=True), False, False, 0)
    bar = Gtk.ProgressBar()
    bar.get_style_context().add_class("thin")
    bar.set_fraction(min(1.0, size / largest) if largest else 0)
    middle.pack_start(bar, False, False, 0)
    outer.pack_start(middle, True, True, 0)
    if when:
        outer.pack_start(label(when, "faint", xalign=1.0), False, False, 0)
    size_label = label(core.format_bytes(size), "dim", xalign=1.0)
    size_label.set_width_chars(10)
    outer.pack_start(size_label, False, False, 0)
    if folder is not None:
        open_btn = Gtk.Button.new_from_icon_name("folder-open-symbolic", Gtk.IconSize.BUTTON)
        open_btn.set_relief(Gtk.ReliefStyle.NONE)
        open_btn.set_tooltip_text("Mostra nella cartella")
        open_btn.connect("clicked", lambda _b: open_folder(folder))
        outer.pack_start(open_btn, False, False, 0)
    row.add(outer)
    return row


def card_list(rows: list) -> Gtk.Widget:
    frame = Gtk.Box()
    frame.get_style_context().add_class("card")
    lb = Gtk.ListBox()
    lb.set_selection_mode(Gtk.SelectionMode.NONE)
    for i, r in enumerate(rows):
        lb.add(r)
    frame.pack_start(lb, True, True, 0)
    return frame


def page_header(icon: str, color: str, title: str, subtitle: str, safety: str | None = None, right: Gtk.Widget | None = None):
    box = Gtk.Box(spacing=14, valign=Gtk.Align.START)
    box.pack_start(tile(icon, color, 48), False, False, 0)
    text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    head = Gtk.Box(spacing=8)
    head.pack_start(label(title, "page-title"), False, False, 0)
    if safety:
        head.pack_start(badge("Sicuro" if safety == "safe" else "Attenzione", safety), False, False, 0)
    text.pack_start(head, False, False, 0)
    text.pack_start(label(subtitle, "dim", wrap=True), False, False, 0)
    box.pack_start(text, True, True, 0)
    if right is not None:
        box.pack_end(right, False, False, 0)
    return box


def scrolled(child: Gtk.Widget) -> Gtk.ScrolledWindow:
    sw = Gtk.ScrolledWindow()
    sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    sw.add(child)
    return sw


def page_body(margin: int = 28) -> Gtk.Box:
    return Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20, margin=margin)


def size_block(total: int, count_text: str) -> Gtk.Widget:
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    box.pack_start(label(core.format_bytes(total), "big-size", xalign=1.0), False, False, 0)
    box.pack_start(label(count_text, "dim", xalign=1.0), False, False, 0)
    return box


# MARK: - Model -------------------------------------------------------------------------------------

class Model:
    def __init__(self, on_change):
        self.categories = core.all_categories()
        self.items: dict = {}
        self.scanning: set = set()
        self.selected: dict = {}
        self.on_change = on_change
        self._gate = threading.Semaphore(4)

    def by_group(self, group: str) -> list:
        return [c for c in self.categories if c.group == group]

    def size(self, cat) -> int:
        return sum(i.size for i in self.items.get(cat.id, []))

    def scan(self, cat) -> None:
        if cat.id in self.scanning:
            return
        self.scanning.add(cat.id)

        def work():
            with self._gate:
                return core.scan_category(cat)

        def done(result):
            self.scanning.discard(cat.id)
            self.items[cat.id] = result if isinstance(result, list) else []
            self.on_change(cat.id)

        background(work, done)

    def scan_all(self) -> None:
        for c in self.categories:
            self.scan(c)

    def smart_items(self) -> list:
        return core.smart_clean_items(self.items, self.categories)

    def trash_selected(self, cat) -> None:
        ids = self.selected.get(cat.id, set())
        paths = [i.path for i in self.items.get(cat.id, []) if i.id in ids and not core.is_inside_repo(i.path)]
        core.trash(paths)
        self.selected[cat.id] = set()
        self.items[cat.id] = [i for i in self.items.get(cat.id, []) if i.id not in ids]
        self.scan(cat)

    def smart_clean(self) -> None:
        core.trash([i.path for i in self.smart_items()])
        self.scan_all()


# MARK: - Pages -------------------------------------------------------------------------------------

class OverviewPage:
    def __init__(self, win: "MainWindow"):
        self.win = win
        self.widget = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.body = page_body()
        self.widget.pack_start(scrolled(self.body), True, True, 0)

    def refresh(self) -> None:
        m = self.win.model
        clear(self.body)
        safe_total = sum(m.size(c) for c in m.categories if c.safety == "safe")
        caution_total = sum(m.size(c) for c in m.categories if c.safety == "caution")
        scanning = bool(m.scanning)

        hero = Gtk.Box(spacing=28)
        hero.get_style_context().add_class("hero")
        ring = Gtk.DrawingArea()
        ring.set_size_request(150, 150)
        ring.connect("draw", self._draw_ring)
        hero.pack_start(ring, False, False, 0)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, valign=Gtk.Align.CENTER)
        text.pack_start(label("Analisi in corso…" if scanning else "Puoi liberare in sicurezza", "hero-sub"), False, False, 0)
        text.pack_start(label(core.format_bytes(safe_total), "hero-total"), False, False, 0)
        text.pack_start(label(f"+ {core.format_bytes(caution_total)} da valutare caso per caso", "hero-sub"), False, False, 0)
        buttons = Gtk.Box(spacing=10, margin_top=8)
        smart = button("Pulizia intelligente", "on-hero", "emblem-system-symbolic")
        smart.set_sensitive(not scanning and bool(m.smart_items()))
        smart.connect("clicked", lambda _b: self.win.smart_clean())
        buttons.pack_start(smart, False, False, 0)
        trash_size = core.trash_size()
        empty = button(f"Svuota il Cestino ({core.format_bytes(trash_size)})", "on-hero-ghost", "user-trash-symbolic")
        empty.set_sensitive(trash_size > 0)
        empty.connect("clicked", lambda _b: self.win.empty_trash())
        buttons.pack_start(empty, False, False, 0)
        if scanning:
            buttons.pack_start(Gtk.Spinner(active=True), False, False, 0)
        text.pack_start(buttons, False, False, 0)
        hero.pack_start(text, True, True, 0)
        self.body.pack_start(hero, False, False, 0)

        ai_total = sum(m.size(c) for c in m.by_group("ai"))
        banner = Gtk.Box(spacing=16)
        banner.get_style_context().add_class("ai-banner")
        banner.pack_start(tile("starred-symbolic", "ink", 52), False, False, 0)
        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3, valign=Gtk.Align.CENTER)
        inner.pack_start(label("Liberati dai file dell'AI", "section-title"), False, False, 0)
        inner.pack_start(label("Temporanei, copie prima delle modifiche e backup lasciati da Claude Code e Codex. I tuoi progetti git non vengono mai toccati.", wrap=True), False, False, 0)
        banner.pack_start(inner, True, True, 0)
        total = label(core.format_bytes(ai_total), "big-size")
        banner.pack_end(total, False, False, 0)
        self.body.pack_start(banner, False, False, 0)

        for title, sub, group in (("Creati dall'AI", "Temporanei e backup di Claude Code e Codex", "ai"),
                                  ("Privacy", "Cronologia e cookie: chiudi prima i browser", "privacy"),
                                  ("Cache e temporanei", "Vengono rigenerati automaticamente", "cleanup")):
            self.body.pack_start(self._section(title, sub, sorted(m.by_group(group), key=lambda c: -m.size(c))), False, False, 0)

        tools = [("Mappa dello spazio", "Vedi a blocchi cosa occupa più spazio ed entra nelle cartelle", "view-grid-symbolic", "indigo", "tool:map"),
                 ("File grandi e vecchi", "I file pesanti che non apri da mesi, fuori dai tuoi progetti git", "document-open-recent-symbolic", "orchid", "tool:large"),
                 ("File duplicati", "Copie identiche in Scaricati, Scrivania e Documenti", "edit-copy-symbolic", "plum", "tool:dups"),
                 ("Elementi di avvio", "Programmi che partono da soli all'accesso", "system-run-symbolic", "mauve", "tool:startup")]
        flow = self._flow()
        for title, detail, icon, color, key in tools:
            flow.add(self._card(icon, color, title, detail, key))
        section = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        section.pack_start(label("Strumenti", "section-title"), False, False, 0)
        section.pack_start(flow, False, False, 0)
        self.body.pack_start(section, False, False, 0)
        self.body.show_all()

    def _flow(self) -> Gtk.FlowBox:
        flow = Gtk.FlowBox()
        flow.set_selection_mode(Gtk.SelectionMode.NONE)
        flow.set_max_children_per_line(4)
        flow.set_min_children_per_line(2)
        flow.set_column_spacing(14)
        flow.set_row_spacing(14)
        flow.set_homogeneous(True)
        return flow

    def _section(self, title: str, sub: str, cats: list) -> Gtk.Widget:
        m = self.win.model
        section = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        head = Gtk.Box(spacing=10)
        head.pack_start(label(title, "section-title"), False, False, 0)
        head.pack_start(label(sub, "dim"), False, False, 0)
        section.pack_start(head, False, False, 0)
        flow = self._flow()
        clean = []
        for c in cats:
            if m.size(c) == 0 and c.id not in m.scanning:
                clean.append(c)
                continue
            flow.add(self._card(c.icon, c.color, c.title, None, f"cat:{c.id}", c))
        section.pack_start(flow, False, False, 0)
        if clean:
            row = Gtk.Box(spacing=8)
            row.pack_start(Gtk.Image.new_from_icon_name("emblem-ok-symbolic", Gtk.IconSize.BUTTON), False, False, 0)
            row.pack_start(label("Già puliti: " + ", ".join(c.title for c in clean), "dim"), False, False, 0)
            section.pack_start(row, False, False, 0)
        return section

    def _card(self, icon: str, color: str, title: str, detail: str | None, key: str, cat=None) -> Gtk.Widget:
        m = self.win.model
        btn = Gtk.Button()
        btn.get_style_context().add_class("card-button")
        btn.set_relief(Gtk.ReliefStyle.NONE)
        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=14)
        top = Gtk.Box()
        top.pack_start(tile(icon, color, 36), False, False, 0)
        if cat is not None:
            top.pack_end(badge("Sicuro" if cat.safety == "safe" else "Attenzione", cat.safety), False, False, 0)
        inner.pack_start(top, False, False, 0)
        inner.pack_start(label(title, "dim", ellipsize=True), False, False, 0)
        if cat is not None:
            if cat.id in m.scanning:
                inner.pack_start(Gtk.Spinner(active=True), False, False, 0)
            else:
                inner.pack_start(label(core.format_bytes(m.size(cat)), "big-size"), False, False, 0)
        elif detail:
            inner.pack_start(label(detail, "faint", wrap=True), False, False, 0)
        btn.add(inner)
        btn.connect("clicked", lambda _b: self.win.show_page(key))
        return btn

    def _draw_ring(self, area, cr) -> bool:
        w, h = area.get_allocated_width(), area.get_allocated_height()
        cx, cy, r = w / 2, h / 2, min(w, h) / 2 - 10
        usage = shutil.disk_usage(str(core.home()))
        frac = usage.used / usage.total if usage.total else 0
        cr.set_line_width(14)
        cr.set_source_rgba(1, 1, 1, 0.2)
        cr.arc(cx, cy, r, 0, 6.2832)
        cr.stroke()
        cr.set_source_rgb(0.996, 0.341, 0.651)
        cr.set_line_cap(1)
        cr.arc(cx, cy, r, -1.5708, -1.5708 + 6.2832 * frac)
        cr.stroke()
        cr.set_source_rgb(1, 1, 1)
        cr.select_font_face("Sans", 0, 1)
        cr.set_font_size(18)
        text = core.format_bytes(usage.free)
        ext = cr.text_extents(text)
        cr.move_to(cx - ext.width / 2, cy)
        cr.show_text(text)
        cr.select_font_face("Sans", 0, 0)
        cr.set_font_size(11)
        sub = f"liberi su {core.format_bytes(usage.total)}"
        ext = cr.text_extents(sub)
        cr.move_to(cx - ext.width / 2, cy + 18)
        cr.show_text(sub)
        return False


class CategoryPage:
    def __init__(self, win: "MainWindow", cat):
        self.win, self.cat = win, cat
        self.widget = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.body = page_body()
        self.widget.pack_start(scrolled(self.body), True, True, 0)
        self.bar = ActionBar(self.deselect, self.trash)
        self.widget.pack_end(self.bar, False, False, 0)

    @property
    def selected(self) -> set:
        return self.win.model.selected.setdefault(self.cat.id, set())

    def deselect(self) -> None:
        self.selected.clear()
        self.refresh()

    def trash(self) -> None:
        sel = self.selected
        size = sum(i.size for i in self.win.model.items.get(self.cat.id, []) if i.id in sel)
        if confirm(self.win, f"Spostare {len(sel)} elementi nel Cestino?",
                   f"Libererai circa {core.format_bytes(size)}. Potrai recuperarli dal Cestino finché non lo svuoti."):
            self.win.model.trash_selected(self.cat)
            self.refresh()

    def refresh(self) -> None:
        m, cat = self.win.model, self.cat
        items = m.items.get(cat.id, [])
        clear(self.body)
        self.body.pack_start(page_header(cat.icon, cat.color, cat.title, cat.explanation, cat.safety,
                                         size_block(m.size(cat), f"{len(items)} elementi")), False, False, 0)
        if cat.id in m.scanning:
            row = Gtk.Box(spacing=10, halign=Gtk.Align.CENTER, margin=30)
            row.pack_start(Gtk.Spinner(active=True), False, False, 0)
            row.pack_start(label("Analisi in corso…", "dim"), False, False, 0)
            self.body.pack_start(row, False, False, 0)
        elif not items:
            self.body.pack_start(label("Tutto pulito: non c'è niente da eliminare in questa categoria.", "dim", xalign=0.5), False, False, 30)
        else:
            tools = Gtk.Box(spacing=8)
            all_btn = button("Seleziona tutto")
            all_btn.connect("clicked", lambda _b: self._select_all())
            tools.pack_start(all_btn, False, False, 0)
            self.body.pack_start(tools, False, False, 0)
            largest = max(i.size for i in items)
            rows = []
            for it in items:
                badges = []
                if it.contains_repo:
                    badges.append(badge("repository git", "repo", "Contiene un repository git: non viene mai preselezionato"))
                if it.is_recent:
                    badges.append(badge("in uso?", "warn", "Modificato nelle ultime 6 ore: potrebbe essere ancora in uso"))
                rows.append(item_row(it.display_name, it.size, it.id in self.selected, self._toggler(it.id), largest,
                                     when=relative(it.modified), badges=badges, folder=it.path))
            self.body.pack_start(card_list(rows), False, False, 0)
        selected_items = [i for i in items if i.id in self.selected]
        self.bar.update(len(selected_items), sum(i.size for i in selected_items))
        self.body.show_all()

    def _toggler(self, item_id: str):
        def toggle(active: bool):
            (self.selected.add if active else self.selected.discard)(item_id)
            items = self.win.model.items.get(self.cat.id, [])
            chosen = [i for i in items if i.id in self.selected]
            self.bar.update(len(chosen), sum(i.size for i in chosen))
        return toggle

    def _select_all(self) -> None:
        self.selected.clear()
        self.selected.update(i.id for i in self.win.model.items.get(self.cat.id, []) if not i.contains_repo and not i.is_recent)
        self.refresh()


class DiskMapPage:
    PALETTE = ["#C2185F", "#8C3399", "#4540B8", "#CC4DB3", "#8066B8", "#5C6180"]

    def __init__(self, win: "MainWindow"):
        self.win = win
        self.path = [core.home()]
        self.nodes: list = []
        self.rects: list = []
        self.loading = False
        self.selected: set = set()
        self.generation = 0
        self.widget = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.body = page_body()
        self.widget.pack_start(scrolled(self.body), True, True, 0)
        self.bar = ActionBar(self._deselect, self._trash)
        self.widget.pack_end(self.bar, False, False, 0)
        self.area = Gtk.DrawingArea()
        self.area.set_size_request(-1, 380)
        self.area.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.area.connect("draw", self._draw)
        self.area.connect("button-press-event", self._click)
        self.area.set_has_tooltip(True)
        self.area.connect("query-tooltip", self._tooltip)
        self.started = False

    def on_show(self) -> None:
        if not self.started:
            self.started = True
            self.load()

    def load(self) -> None:
        self.generation += 1
        token = self.generation
        self.loading, self.nodes, self.selected = True, [], set()
        folder = self.path[-1]

        def on_node(node):
            def add():
                if token == self.generation:
                    self.nodes.append(node)
                    self.nodes.sort(key=lambda n: -n.size)
                    self.refresh(light=True)
                return False
            GLib.idle_add(add)

        def finished(_r):
            if token == self.generation:
                self.loading = False
                self.refresh()

        background(lambda: core.scan_children(folder, on_node), finished)
        self.refresh()

    def _deselect(self) -> None:
        self.selected.clear()
        self.refresh()

    def _trash(self) -> None:
        chosen = [n for n in self.nodes if n.path.as_posix() in self.selected and not n.protected]
        size = sum(n.size for n in chosen)
        if confirm(self.win, f"Spostare {len(chosen)} elementi nel Cestino?",
                   f"Libererai circa {core.format_bytes(size)}. Potrai recuperarli dal Cestino finché non lo svuoti."):
            core.trash([n.path for n in chosen])
            self.load()

    def refresh(self, light: bool = False) -> None:
        # The drawing area outlives page rebuilds: take it out before its old container is destroyed.
        if self.area.get_parent() is not None:
            self.area.get_parent().remove(self.area)
        clear(self.body)
        total = sum(n.size for n in self.nodes)
        self.body.pack_start(page_header(
            "view-grid-symbolic", "indigo", "Mappa dello spazio",
            "Ogni blocco è una cartella o un file: più è grande, più spazio occupa. Clicca una cartella per entrarci. Le cartelle con repository git sono bloccate e non si possono eliminare da qui.",
            None, size_block(total, f"{len(self.nodes)} elementi")), False, False, 0)
        crumbs = Gtk.Box(spacing=6)
        for i, p in enumerate(self.path):
            if i:
                crumbs.pack_start(label("›", "dim"), False, False, 0)
            name = "Home" if i == 0 and p == core.home() else (p.name or "/")
            b = Gtk.Button(label=name)
            b.set_relief(Gtk.ReliefStyle.NONE)
            b.connect("clicked", lambda _b, idx=i: self._go(idx))
            crumbs.pack_start(b, False, False, 0)
        start = Gtk.MenuButton(label="Parti da")
        menu = Gtk.Menu()
        for text, target in (("Home", core.home()), ("Disco (/)", Path("/"))):
            item = Gtk.MenuItem(label=text)
            item.connect("activate", lambda _i, t=target: self._choose(t))
            menu.append(item)
        other = Gtk.MenuItem(label="Altra cartella…")
        other.connect("activate", lambda _i: self._pick())
        menu.append(other)
        menu.show_all()
        start.set_popup(menu)
        crumbs.pack_end(start, False, False, 0)
        self.body.pack_start(crumbs, False, False, 0)
        if self.loading:
            row = Gtk.Box(spacing=8)
            row.pack_start(Gtk.Spinner(active=True), False, False, 0)
            row.pack_start(label("Sto misurando le cartelle…", "dim"), False, False, 0)
            self.body.pack_start(row, False, False, 0)
        if self.nodes:
            frame = Gtk.Box()
            frame.get_style_context().add_class("card")
            frame.pack_start(self.area, True, True, 0)
            self.body.pack_start(frame, False, False, 0)
            largest = self.nodes[0].size
            rows = []
            for n in self.nodes[:200]:
                badges = [badge("repository git", "repo")] if n.protected else []
                rows.append(item_row(n.path.name, n.size, n.path.as_posix() in self.selected, self._toggler(n),
                                     largest, badges=badges, folder=n.path, checkable=not n.protected))
            self.body.pack_start(card_list(rows), False, False, 0)
        elif not self.loading:
            self.body.pack_start(label("Qui non c'è niente che occupi spazio.", "dim", xalign=0.5), False, False, 30)
        chosen = [n for n in self.nodes if n.path.as_posix() in self.selected]
        self.bar.update(len(chosen), sum(n.size for n in chosen))
        self.body.show_all()
        self.area.queue_draw()

    def _toggler(self, node):
        def toggle(active: bool):
            key = node.path.as_posix()
            (self.selected.add if active else self.selected.discard)(key)
            chosen = [n for n in self.nodes if n.path.as_posix() in self.selected]
            self.bar.update(len(chosen), sum(n.size for n in chosen))
            self.area.queue_draw()
        return toggle

    def _go(self, index: int) -> None:
        if index < len(self.path) - 1:
            self.path = self.path[:index + 1]
            self.load()

    def _choose(self, target: Path) -> None:
        self.path = [target]
        self.load()

    def _pick(self) -> None:
        dialog = Gtk.FileChooserDialog(title="Scegli una cartella", transient_for=self.win,
                                       action=Gtk.FileChooserAction.SELECT_FOLDER)
        dialog.add_buttons("Annulla", Gtk.ResponseType.CANCEL, "Scegli", Gtk.ResponseType.OK)
        if dialog.run() == Gtk.ResponseType.OK:
            self._choose(Path(dialog.get_filename()))
        dialog.destroy()

    def _layout(self, w: float, h: float) -> list:
        shown = self.nodes[:60]
        return list(zip(shown, core.squarify([n.size for n in shown], 0, 0, w, h)))

    def _draw(self, area, cr) -> bool:
        w, h = area.get_allocated_width(), area.get_allocated_height()
        self.rects = self._layout(w, h)
        for i, (node, (x, y, rw, rh)) in enumerate(self.rects):
            color = Gdk.RGBA()
            color.parse(self.PALETTE[i % len(self.PALETTE)] if node.is_dir else "#33266B")
            cr.set_source_rgba(color.red, color.green, color.blue, 0.45 if node.protected else 0.92)
            cr.rectangle(x + 1, y + 1, max(rw - 2, 0), max(rh - 2, 0))
            cr.fill()
            if node.path.as_posix() in self.selected:
                cr.set_source_rgb(0.996, 0.341, 0.651)
                cr.set_line_width(3)
                cr.rectangle(x + 2, y + 2, max(rw - 4, 0), max(rh - 4, 0))
                cr.stroke()
            if rw > 80 and rh > 40:
                cr.set_source_rgb(1, 1, 1)
                cr.select_font_face("Sans", 0, 1)
                cr.set_font_size(12)
                cr.move_to(x + 8, y + 18)
                cr.show_text(("🔒 " if node.protected else "") + node.path.name[: int(rw / 8)])
                cr.select_font_face("Sans", 0, 0)
                cr.set_font_size(11)
                cr.move_to(x + 8, y + 33)
                cr.show_text(core.format_bytes(node.size))
        return False

    def _hit(self, x: float, y: float):
        for node, (rx, ry, rw, rh) in self.rects:
            if rx <= x <= rx + rw and ry <= y <= ry + rh:
                return node
        return None

    def _click(self, _area, event) -> bool:
        node = self._hit(event.x, event.y)
        if node is None:
            return False
        if node.is_dir:
            self.path.append(node.path)
            self.load()
        elif not node.protected:
            key = node.path.as_posix()
            (self.selected.discard if key in self.selected else self.selected.add)(key)
            self.refresh()
        return True

    def _tooltip(self, _area, x, y, _kb, tooltip) -> bool:
        node = self._hit(x, y)
        if node is None:
            return False
        tooltip.set_text(f"{node.path.name} — {core.format_bytes(node.size)}")
        return True


class DuplicatesPage:
    def __init__(self, win: "MainWindow"):
        self.win = win
        self.folders = core.default_duplicate_folders()
        self.groups: list = []
        self.selected: set = set()
        self.scanning = False
        self.progress = ""
        self.scanned = False
        self.widget = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.body = page_body()
        self.widget.pack_start(scrolled(self.body), True, True, 0)
        self.bar = ActionBar(self._deselect, self._trash)
        self.widget.pack_end(self.bar, False, False, 0)

    def on_show(self) -> None:
        if os.environ.get("DUSTBUSTER_AUTOSCAN") and not self.scanned and not self.scanning:
            self.scan()

    def _deselect(self) -> None:
        self.selected.clear()
        self.refresh()

    def _ok(self) -> bool:
        return all(any(f.path.as_posix() not in self.selected for f in g.files) for g in self.groups)

    def _trash(self) -> None:
        if not self._ok():
            info(self.win, "Tieni almeno una copia", "In ogni gruppo deve restare almeno una copia.")
            return
        chosen = [f for g in self.groups for f in g.files if f.path.as_posix() in self.selected]
        if confirm(self.win, f"Spostare {len(chosen)} duplicati nel Cestino?",
                   f"Per ogni gruppo rimane almeno una copia. Libererai circa {core.format_bytes(sum(f.size for f in chosen))}."):
            core.trash([f.path for f in chosen if not core.is_inside_repo(f.path)])
            self.scan()

    def scan(self) -> None:
        if self.scanning:
            return
        self.scanning, self.groups, self.selected = True, [], set()

        def progress(name):
            self.progress = name

        def work():
            return core.find_duplicates(self.folders, progress)

        def done(result):
            self.scanning = False
            self.scanned = True
            self.groups = result if isinstance(result, list) else []
            self.selected = {f.path.as_posix() for g in self.groups for f in g.files[1:]}
            self.refresh()

        background(work, done)
        self.refresh()

    def refresh(self) -> None:
        clear(self.body)
        wasted = sum(g.wasted for g in self.groups)
        self.body.pack_start(page_header(
            "edit-copy-symbolic", "plum", "File duplicati",
            "Cerca file con contenuto identico nelle cartelle scelte. In ogni gruppo la copia più vecchia resta deselezionata e non viene mai toccata. I file nei repository git e nelle cartelle di dipendenze sono ignorati.",
            None, size_block(wasted, f"{len(self.groups)} gruppi") if self.groups else None), False, False, 0)
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        card.get_style_context().add_class("card")
        card.pack_start(label("Cartelle da analizzare", "section-title"), False, False, 0)
        flow = Gtk.FlowBox()
        flow.set_selection_mode(Gtk.SelectionMode.NONE)
        for folder in self.folders:
            chip = Gtk.Box(spacing=6)
            chip.pack_start(Gtk.Image.new_from_icon_name("folder-symbolic", Gtk.IconSize.BUTTON), False, False, 0)
            chip.pack_start(label(folder.name), False, False, 0)
            rm = Gtk.Button.new_from_icon_name("window-close-symbolic", Gtk.IconSize.BUTTON)
            rm.set_relief(Gtk.ReliefStyle.NONE)
            rm.connect("clicked", lambda _b, f=folder: self._remove(f))
            chip.pack_start(rm, False, False, 0)
            flow.add(chip)
        card.pack_start(flow, False, False, 0)
        actions = Gtk.Box(spacing=10)
        add = button("Aggiungi cartella", "", "list-add-symbolic")
        add.connect("clicked", lambda _b: self._add())
        actions.pack_start(add, False, False, 0)
        if self.scanning:
            actions.pack_start(Gtk.Spinner(active=True), False, False, 0)
            actions.pack_start(label(self.progress, "faint", ellipsize=True), False, False, 0)
        go = button("Avvia scansione", "accent", "system-search-symbolic")
        go.set_sensitive(bool(self.folders) and not self.scanning)
        go.connect("clicked", lambda _b: self.scan())
        actions.pack_end(go, False, False, 0)
        card.pack_start(actions, False, False, 0)
        self.body.pack_start(card, False, False, 0)
        if self.scanned and not self.scanning:
            if not self.groups:
                self.body.pack_start(label("Nessun duplicato trovato.", "dim", xalign=0.5), False, False, 20)
            for g in self.groups[:300]:
                rows = []
                for f in g.files:
                    key = f.path.as_posix()
                    kept = key not in self.selected
                    rows.append(item_row(f.path.name, f.size, not kept, self._toggler(key), f.size,
                                         subtitle=str(f.path.parent), when=relative(f.modified),
                                         badges=[badge("tenuto", "safe")] if kept else [], folder=f.path))
                box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
                box.pack_start(label(f"{len(g.files)} copie · recuperabili {core.format_bytes(g.wasted)}", "dim"), False, False, 0)
                box.pack_start(card_list(rows), False, False, 0)
                self.body.pack_start(box, False, False, 0)
        self._update_bar()
        self.body.show_all()

    def _update_bar(self) -> None:
        chosen = [f for g in self.groups for f in g.files if f.path.as_posix() in self.selected]
        self.bar.update(len(chosen), sum(f.size for f in chosen))
        self.bar.trash_button.set_sensitive(self._ok())

    def _toggler(self, key: str):
        def toggle(active: bool):
            (self.selected.add if active else self.selected.discard)(key)
            self._update_bar()
        return toggle

    def _remove(self, folder: Path) -> None:
        self.folders.remove(folder)
        self.refresh()

    def _add(self) -> None:
        dialog = Gtk.FileChooserDialog(title="Aggiungi una cartella", transient_for=self.win,
                                       action=Gtk.FileChooserAction.SELECT_FOLDER)
        dialog.add_buttons("Annulla", Gtk.ResponseType.CANCEL, "Aggiungi", Gtk.ResponseType.OK)
        if dialog.run() == Gtk.ResponseType.OK:
            folder = Path(dialog.get_filename())
            if folder not in self.folders:
                self.folders.append(folder)
        dialog.destroy()
        self.refresh()


class LargeFilesPage:
    SIZES = [("100 MB", 100), ("500 MB", 500), ("1 GB", 1000), ("5 GB", 5000)]
    AGES = [("Qualsiasi data", 0), ("3 mesi", 3), ("6 mesi", 6), ("1 anno", 12)]

    def __init__(self, win: "MainWindow"):
        self.win = win
        self.files: list = []
        self.selected: set = set()
        self.scanning = False
        self.scanned = False
        self.size_idx, self.age_idx = 1, 2
        self.widget = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.body = page_body()
        self.widget.pack_start(scrolled(self.body), True, True, 0)
        self.bar = ActionBar(self._deselect, self._trash)
        self.widget.pack_end(self.bar, False, False, 0)

    def on_show(self) -> None:
        if os.environ.get("DUSTBUSTER_AUTOSCAN") and not self.scanned and not self.scanning:
            self.scan()

    def _deselect(self) -> None:
        self.selected.clear()
        self.refresh()

    def _trash(self) -> None:
        chosen = [f for f in self.files if f.path.as_posix() in self.selected]
        if confirm(self.win, f"Spostare {len(chosen)} file nel Cestino?",
                   f"Libererai circa {core.format_bytes(sum(f.size for f in chosen))}. Potrai recuperarli dal Cestino finché non lo svuoti."):
            core.trash([f.path for f in chosen if not core.is_inside_repo(f.path)])
            self.files = [f for f in self.files if f.path.as_posix() not in self.selected]
            self.selected.clear()
            self.refresh()

    def scan(self) -> None:
        if self.scanning:
            return
        self.scanning, self.files, self.selected = True, [], set()
        min_bytes = self.SIZES[self.size_idx][1] * 1_000_000
        months = self.AGES[self.age_idx][1]
        cutoff = time.time() - months * 30 * 86400 if months else None

        def done(result):
            self.scanning, self.scanned = False, True
            self.files = result if isinstance(result, list) else []
            self.refresh()

        background(lambda: core.find_large_files(core.large_file_roots(), min_bytes, cutoff), done)
        self.refresh()

    def refresh(self) -> None:
        clear(self.body)
        total = sum(f.size for f in self.files)
        self.body.pack_start(page_header(
            "document-open-recent-symbolic", "orchid", "File grandi e vecchi",
            "Trova in Scaricati, Scrivania, Documenti, Video, Musica e Immagini i file pesanti che non apri da tempo. I file dentro repository git non compaiono mai.",
            None, size_block(total, f"{len(self.files)} file") if self.scanned else None), False, False, 0)
        card = Gtk.Box(spacing=16)
        card.get_style_context().add_class("card")
        card.pack_start(label("Più grandi di"), False, False, 0)
        size_combo = Gtk.ComboBoxText()
        for text, _ in self.SIZES:
            size_combo.append_text(text)
        size_combo.set_active(self.size_idx)
        size_combo.connect("changed", lambda c: setattr(self, "size_idx", c.get_active()))
        card.pack_start(size_combo, False, False, 0)
        card.pack_start(label("Non aperti da"), False, False, 0)
        age_combo = Gtk.ComboBoxText()
        for text, _ in self.AGES:
            age_combo.append_text(text)
        age_combo.set_active(self.age_idx)
        age_combo.connect("changed", lambda c: setattr(self, "age_idx", c.get_active()))
        card.pack_start(age_combo, False, False, 0)
        if self.scanning:
            card.pack_start(Gtk.Spinner(active=True), False, False, 0)
        go = button("Cerca", "accent", "system-search-symbolic")
        go.set_sensitive(not self.scanning)
        go.connect("clicked", lambda _b: self.scan())
        card.pack_end(go, False, False, 0)
        self.body.pack_start(card, False, False, 0)
        if self.scanned and not self.scanning:
            if not self.files:
                self.body.pack_start(label("Nessun file trovato. Prova con una soglia più bassa o una data più vicina.", "dim", xalign=0.5), False, False, 20)
            else:
                largest = self.files[0].size
                rows = [item_row(f.path.name, f.size, f.path.as_posix() in self.selected, self._toggler(f.path.as_posix()),
                                 largest, subtitle=str(f.path.parent).replace(str(core.home()), "~", 1),
                                 when=relative(f.last_touched), folder=f.path) for f in self.files[:300]]
                self.body.pack_start(card_list(rows), False, False, 0)
        self._update_bar()
        self.body.show_all()

    def _update_bar(self) -> None:
        chosen = [f for f in self.files if f.path.as_posix() in self.selected]
        self.bar.update(len(chosen), sum(f.size for f in chosen))

    def _toggler(self, key: str):
        def toggle(active: bool):
            (self.selected.add if active else self.selected.discard)(key)
            self._update_bar()
        return toggle


class StartupPage:
    def __init__(self, win: "MainWindow"):
        self.win = win
        self.items: list = []
        self.widget = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.body = page_body()
        self.widget.pack_start(scrolled(self.body), True, True, 0)

    def on_show(self) -> None:
        background(core.scan_startup, self._loaded)

    def _loaded(self, result) -> None:
        self.items = result if isinstance(result, list) else []
        self.refresh()

    def refresh(self) -> None:
        clear(self.body)
        self.body.pack_start(page_header(
            "system-run-symbolic", "mauve", "Elementi di avvio",
            "Programmi che partono da soli quando accedi. L'interruttore li disattiva senza eliminare nulla: puoi riattivarli quando vuoi. Quelli di sistema vengono disattivati solo per il tuo utente.",
            None, None), False, False, 0)
        broken = [i for i in self.items if i.program_missing]
        if broken:
            text = ("1 elemento punta a un programma che non esiste più" if len(broken) == 1
                    else f"{len(broken)} elementi puntano a un programma che non esiste più")
            self.body.pack_start(label(text + ": di solito sono resti di app rimosse.", "badge badge-warn"), False, False, 0)
        if not self.items:
            self.body.pack_start(label("Nessun elemento di avvio trovato.", "dim", xalign=0.5), False, False, 20)
        rows = []
        for it in self.items:
            row = Gtk.ListBoxRow()
            row.set_activatable(False)
            box = Gtk.Box(spacing=12, margin=10)
            text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            head = Gtk.Box(spacing=6)
            head.pack_start(label(it.name, ellipsize=True), False, False, 0)
            if it.program_missing:
                head.pack_start(badge("programma mancante", "warn"), False, False, 0)
            text.pack_start(head, False, False, 0)
            text.pack_start(label(it.exec_line, "faint", ellipsize=True), False, False, 0)
            box.pack_start(text, True, True, 0)
            box.pack_start(label("Sistema" if it.scope == "system" else "Tuo utente", "faint"), False, False, 0)
            switch = Gtk.Switch()
            switch.set_active(it.enabled)
            switch.set_valign(Gtk.Align.CENTER)
            switch.connect("state-set", lambda _s, state, i=it: self._toggle(i, state))
            box.pack_start(switch, False, False, 0)
            row.add(box)
            rows.append(row)
        if rows:
            self.body.pack_start(card_list(rows), False, False, 0)
        self.body.show_all()

    def _toggle(self, item, state: bool) -> bool:
        try:
            core.set_startup_enabled(item, state)
        except OSError as e:
            info(self.win, "Non riesco a modificare l'elemento", str(e))
        return False


# MARK: - Window ------------------------------------------------------------------------------------

STATE_FILE = lambda: core.home() / ".config/dustbuster/state.json"  # noqa: E731


def load_state() -> dict:
    try:
        return json.loads(STATE_FILE().read_text())
    except (OSError, ValueError):
        return {}


def save_state(state: dict) -> None:
    try:
        STATE_FILE().parent.mkdir(parents=True, exist_ok=True)
        STATE_FILE().write_text(json.dumps(state))
    except OSError:
        pass


class MainWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Dustbuster")
        self.set_default_size(1180, 780)
        self.model = Model(self.on_model_change)
        self.release = None
        self.update_state = ""
        self.current = "overview"

        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.set_title("Dustbuster")
        self.set_titlebar(header)
        refresh = Gtk.Button.new_from_icon_name("view-refresh-symbolic", Gtk.IconSize.BUTTON)
        refresh.set_tooltip_text("Rianalizza tutto")
        refresh.connect("clicked", lambda _b: self.model.scan_all())
        header.pack_end(refresh)

        paned = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        self.add(paned)
        paned.pack1(self._build_sidebar(), False, False)
        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        paned.pack2(self.stack, True, False)
        paned.set_position(290)

        self.pages: dict = {"overview": OverviewPage(self), "tool:map": DiskMapPage(self),
                            "tool:large": LargeFilesPage(self), "tool:dups": DuplicatesPage(self),
                            "tool:startup": StartupPage(self)}
        for c in self.model.categories:
            self.pages[f"cat:{c.id}"] = CategoryPage(self, c)
        for key, page in self.pages.items():
            self.stack.add_named(page.widget, key)
        self.show_all()
        self.show_page(os.environ.get("DUSTBUSTER_SECTION", "overview"))
        self.model.scan_all()
        self.pages["overview"].refresh()
        if not os.environ.get("DUSTBUSTER_NO_UPDATE_CHECK"):
            self.check_updates(auto=True)

    # --- sidebar
    def _build_sidebar(self) -> Gtk.Widget:
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.get_style_context().add_class("sidebar")
        self.listbox = Gtk.ListBox()
        self.listbox.get_style_context().add_class("sidebar")
        self.listbox.connect("row-selected", self._row_selected)
        self.rows: dict = {}
        self.size_labels: dict = {}

        def add_group(title: str):
            row = Gtk.ListBoxRow()
            row.set_selectable(False)
            row.set_activatable(False)
            row.add(label(title.upper(), "group-title"))
            row.get_child().set_margin_top(12)
            self.listbox.add(row)

        def add_row(key: str, title: str, icon: str, color: str, with_size: bool = False):
            row = Gtk.ListBoxRow()
            box = Gtk.Box(spacing=10, margin=4)
            box.pack_start(tile(icon, color, 24), False, False, 0)
            box.pack_start(label(title, ellipsize=True), True, True, 0)
            if with_size:
                size = label("", "faint", xalign=1.0)
                self.size_labels[key] = size
                box.pack_end(size, False, False, 0)
            row.add(box)
            self.rows[key] = row
            self.listbox.add(row)

        add_row("overview", "Panoramica", "utilities-system-monitor-symbolic", "accentdeep")
        for title, group in (("Cache e temporanei", "cleanup"), ("Creati dall'AI", "ai"), ("Privacy", "privacy")):
            add_group(title)
            for c in self.model.by_group(group):
                add_row(f"cat:{c.id}", c.title, c.icon, c.color, True)
        add_group("Strumenti")
        add_row("tool:map", "Mappa dello spazio", "view-grid-symbolic", "indigo")
        add_row("tool:large", "File grandi e vecchi", "document-open-recent-symbolic", "orchid")
        add_row("tool:dups", "File duplicati", "edit-copy-symbolic", "plum")
        add_row("tool:startup", "Elementi di avvio", "system-run-symbolic", "mauve")
        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.add(self.listbox)
        outer.pack_start(sw, True, True, 0)

        self.footer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=10)
        outer.pack_end(self.footer, False, False, 0)
        self._build_footer()
        return outer

    def _build_footer(self) -> None:
        clear(self.footer)
        if self.release and core.is_newer(self.release.version, __version__):
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            box.get_style_context().add_class("update-box")
            box.pack_start(label(f"Versione {self.release.version} disponibile", "section-title"), False, False, 0)
            actions = Gtk.Box(spacing=8)
            up = button("Aggiorna e riavvia", "accent")
            up.set_sensitive(self.update_state not in ("downloading", "installing"))
            up.connect("clicked", lambda _b: self.install_update())
            actions.pack_start(up, False, False, 0)
            news = Gtk.LinkButton.new_with_label(self.release.page_url, "Novità")
            actions.pack_start(news, False, False, 0)
            box.pack_start(actions, False, False, 0)
            self.footer.pack_start(box, False, False, 0)
        row = Gtk.Box(spacing=6)
        row.pack_start(label(f"Versione {__version__}", "faint"), False, False, 0)
        check = Gtk.Button(label="Controlla")
        check.set_relief(Gtk.ReliefStyle.NONE)
        check.connect("clicked", lambda _b: self.check_updates())
        row.pack_end(check, False, False, 0)
        self.footer.pack_start(row, False, False, 0)
        if self.update_state and self.update_state not in ("downloading", "installing"):
            lab = label(self.update_state, "faint", wrap=True)
            self.footer.pack_start(lab, False, False, 0)
        elif self.update_state == "downloading":
            self.footer.pack_start(label("Scarico l'aggiornamento…", "faint"), False, False, 0)
        elif self.update_state == "installing":
            self.footer.pack_start(label("Installo… (ti verrà chiesta la password)", "faint"), False, False, 0)
        self.footer.show_all()

    def _row_selected(self, _lb, row) -> None:
        if row is None:
            return
        for key, r in self.rows.items():
            if r is row and key != self.current:
                self.show_page(key)

    def show_page(self, key: str) -> None:
        if key not in self.pages:
            key = "overview"
        self.current = key
        self.listbox.select_row(self.rows[key])
        self.stack.set_visible_child_name(key)
        page = self.pages[key]
        if hasattr(page, "on_show"):
            page.on_show()
        page.refresh()

    def on_model_change(self, cat_id: str) -> None:
        cat = next(c for c in self.model.categories if c.id == cat_id)
        if cat_id in self.size_labels or f"cat:{cat_id}" in self.size_labels:
            lab = self.size_labels.get(f"cat:{cat_id}")
            if lab is not None:
                lab.set_text(core.format_bytes(self.model.size(cat)))
        if self.current in ("overview", f"cat:{cat_id}"):
            self.pages[self.current].refresh()

    # --- actions
    def smart_clean(self) -> None:
        items = self.model.smart_items()
        size = sum(i.size for i in items)
        if confirm(self.win_or_self(), "Pulizia intelligente",
                   f"Sposto nel Cestino {len(items)} elementi sicuri (circa {core.format_bytes(size)}): cache, log, temporanei. "
                   "Restano fuori tutto ciò che è da valutare, modificato di recente o dentro un repository git. Potrai recuperarli dal Cestino."):
            self.model.smart_clean()

    def win_or_self(self):
        return self

    def empty_trash(self) -> None:
        size = core.trash_size()
        if confirm(self, "Svuotare il Cestino?",
                   f"Verranno eliminati definitivamente i file nel Cestino (circa {core.format_bytes(size)}). Questa operazione non si può annullare.",
                   ok="Svuota il Cestino"):
            core.empty_trash()
            self.pages["overview"].refresh()

    # --- updates
    def check_updates(self, auto: bool = False) -> None:
        state = load_state()
        if auto and time.time() - state.get("last_check", 0) < 6 * 3600:
            return
        self.update_state = "checking"

        def done(result):
            if isinstance(result, Exception):
                self.update_state = f"Controllo non riuscito: {result}"
            else:
                self.release = result
                save_state({**load_state(), "last_check": time.time()})
                self.update_state = "" if result and core.is_newer(result.version, __version__) else "È l'ultima versione."
            self._build_footer()

        background(core.latest_release, done)

    def install_update(self) -> None:
        release = self.release
        self.update_state = "downloading"
        self._build_footer()

        def work():
            tmp = Path(tempfile.mkdtemp(prefix="dustbuster-update-"))
            deb = core.download_update(release, tmp)
            core.verify_deb(deb, release.version)
            GLib.idle_add(self._set_installing)
            core.install_deb(deb)
            shutil.rmtree(tmp, ignore_errors=True)

        def done(result):
            if isinstance(result, Exception):
                self.update_state = f"Aggiornamento non riuscito: {result}"
                self._build_footer()
                return
            subprocess.Popen(["/bin/sh", "-c", "sleep 1; exec dustbuster"], start_new_session=True)
            self.get_application().quit()

        background(work, done)

    def _set_installing(self) -> bool:
        self.update_state = "installing"
        self._build_footer()
        return False


class App(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)

    def do_activate(self) -> None:
        win = self.get_active_window()
        if win is None:
            provider = Gtk.CssProvider()
            provider.load_from_data(build_css().encode())
            Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
            win = MainWindow(self)
        win.present()


def main() -> None:
    GLib.set_prgname("dustbuster")           # matches StartupWMClass in the .desktop file
    GLib.set_application_name("Dustbuster")
    Gtk.Window.set_default_icon_name("dustbuster")
    sys.exit(App().run(sys.argv))
