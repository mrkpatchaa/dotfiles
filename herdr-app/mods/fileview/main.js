// File links: lists the files named in the focused terminal (file:// links, full paths,
// ~/ paths and paths relative to its folder), newest first. Type to filter, ↑/↓ and
// Enter to open one at its line with bat in a pane on the right; q closes that pane.
// Opened with cmd-o ("mod.open:fileview" in keys.json). Replaces the old Herdr
// fileview plugin (Ctrl+click on file:// links), which herdr-app can't hook.

import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { focused, spaces, hc, exec, run, theme, props, closeOverlay } from "herdr";

const HISTORY_LINES = 3000;
const MAX_CANDIDATES = 400;

// Keeps only real files. Prints $HOME first, then "original<TAB>resolved" per file.
const CHECK = `printf '%s\\n' "$HOME"
for p; do
  case "$p" in "~/"*) q="$HOME/\${p#"~/"}" ;; *) q="$p" ;; esac
  [ -f "$q" ] && printf '%s\\t%s\\n' "$p" "$q"
done
exit 0`;

// The viewer: bat at the line when it's there, else less.
const VIEW = `p=$1; l=$2
if command -v bat >/dev/null 2>&1; then
  if [ -n "$l" ]; then bat --paging=always --highlight-line "$l" --pager "less -R -j.3 +\${l}g" "$p"
  else bat --paging=always --pager "less -R" "$p"; fi
elif [ -n "$l" ]; then less -R -j.3 "+\${l}g" "$p"
else less -R "$p"; fi`;

// One reference per match: {raw path, line}. Lines are read bottom-up so the newest comes first.
function references(text) {
  const out = [];
  const lines = text.split("\n").reverse();
  for (const line of lines) {
    const found = [];
    for (const m of line.matchAll(/file:\/\/[^\s)\]>"'`]+/g)) {
      const url = m[0];
      let rest = url.slice("file://".length);
      if (!rest.startsWith("/")) rest = rest.slice(Math.max(0, rest.indexOf("/")));
      const [pathPart, frag = ""] = rest.split("#");
      let path;
      try { path = decodeURIComponent(pathPart); } catch { path = pathPart; }
      const lm = frag.match(/^L?(\d+)/);
      found.push(split(path, lm ? lm[1] : ""));
    }
    const plain = line.replace(/file:\/\/[^\s)\]>"'`]+/g, " ");
    for (let token of plain.split(/[\s()[\]{}<>"'`,|]+/)) {
      token = token.replace(/[.,;:!?]+$/, "");
      if (!token || token.includes("://")) continue;
      let lineNo = "";
      const hash = token.match(/^(.*)#L(\d+)(?:-L?\d+)?$/);
      if (hash) { token = hash[1]; lineNo = hash[2]; }
      const ref = split(token, lineNo);
      if (!/^(~\/|\/|\.{1,2}\/)?[\w@+.\-]+(\/[\w@+.\-]+)*$/.test(ref.path)) continue;
      const base = ref.path.split("/").pop();
      // Needs a folder part or a file extension with a letter in it (skips "1.0", "e.g").
      if (!ref.path.includes("/") && !/\.[A-Za-z][\w-]{0,11}$/.test(base)) continue;
      if (/^\d+(\.\d+)*$/.test(base)) continue;
      found.push(ref);
    }
    out.push(...found.reverse());
  }
  return out;
}

// "src/a.ts:12:3" -> {path: "src/a.ts", line: "12"}
function split(path, line) {
  const m = path.match(/^(.+?):(\d+)(?::\d+)?$/);
  if (m) return { path: m[1], line: line || m[2] };
  return { path, line };
}

export default class FileView extends View {
  init(_props, cx) {
    this.input = InputState.new({ placeholder: "Filter files…" });
    this.input.on("change", (_e, cx) => { this.filter = this.input.value(); this.at = 0; cx.notify(); });
    this.input.on("submit", () => this.open(this.rows()[this.at]));
    this.input.focus();
    cx.timer.after(300, () => this.input.focus());
    this.handle = cx.focus_handle();
    this.filter = "";
    this.at = 0;
    this.items = null;
    this.error = null;
    const f = focused();
    this.target = f;
    this.machine = spaces().find((s) => s.id === f?.space)?.machine ?? null;
    cx.spawn(async (cx) => {
      try { this.items = await this.load(f); }
      catch (e) { this.error = String(e?.message ?? e); this.items = []; }
      cx.notify();
    });
  }

  async load(f) {
    if (!f?.terminal) throw new Error("Focus a terminal first");
    const r = await hc(["read", f.terminal, "--json", "--lines", String(HISTORY_LINES)]);
    if (r.code !== 0) throw new Error(r.stderr.trim() || "Could not read the terminal");
    const text = JSON.parse(r.stdout).text ?? "";
    const cwd = f.cwd ?? "";
    const refs = [];
    const seen = new Set();
    for (const ref of references(text)) {
      let abs = ref.path;
      if (!abs.startsWith("/") && !abs.startsWith("~/")) {
        if (!cwd) continue;
        abs = `${cwd}/${abs.replace(/^\.\//, "")}`;
      }
      const key = `${abs}\n${ref.line}`;
      if (seen.has(key)) continue;
      seen.add(key);
      refs.push({ abs, line: ref.line });
      if (refs.length >= MAX_CANDIDATES) break;
    }
    if (!refs.length) return [];
    const unique = [...new Set(refs.map((x) => x.abs))];
    const c = await exec("sh", ["-c", CHECK, "fileview", ...unique], { on: this.machine });
    const [home, ...rows] = c.stdout.split("\n").filter(Boolean);
    const real = new Map(rows.map((row) => row.split("\t")));
    const items = [];
    const shown = new Set();
    for (const ref of refs) {
      const file = real.get(ref.abs);
      if (!file) continue;
      const key = `${file}\n${ref.line}`;
      if (shown.has(key)) continue;
      shown.add(key);
      const label = home && file.startsWith(home + "/") ? "~" + file.slice(home.length) : file;
      items.push({ file, line: ref.line, label: ref.line ? `${label}:${ref.line}` : label });
    }
    return items;
  }

  rows() {
    const f = this.filter.trim().toLowerCase();
    const all = this.items ?? [];
    return f ? all.filter((x) => x.label.toLowerCase().includes(f)) : all;
  }

  close() {
    closeOverlay(props().overlay);
  }

  open(item) {
    if (!item) return;
    this.close();
    const t = this.target;
    // A split needs a real pane; a layout terminal block gets a tab instead.
    run("terminal.open", { argv: ["sh", "-c", VIEW, "fileview", item.file, item.line], place: t?.pane ? "right" : "tab" });
  }

  render(cx) {
    const t = theme();
    const rows = this.rows();
    if (this.at >= rows.length) this.at = Math.max(0, rows.length - 1);
    const name = (label) => {
      const i = label.lastIndexOf("/");
      return [label.slice(0, i + 1), label.slice(i + 1)];
    };
    const status = this.items === null ? "Reading the terminal…"
      : this.error ? this.error
      : rows.length ? null
      : this.filter ? "No match" : "No file paths in this terminal";
    return v_flex().id("fv-root").track_focus(this.handle).size_full().min_h(0).p(18).gap(10)
      .bg(t.popover).text_size(13).text_color(t.foreground)
      .on_key_down((e, cx) => {
        const k = e.key;
        if (k === "escape") return this.close();
        if (!rows.length) return;
        if (k === "down") this.at = (this.at + 1) % rows.length;
        else if (k === "up") this.at = (this.at + rows.length - 1) % rows.length;
        else return;
        cx.stop_propagation();
        cx.notify();
      })
      .child(h_flex().items_center()
        .child(div().flex_1().text_size(15).font_semibold().child("Files in this terminal"))
        .child(div().text_size(11).text_color(t.dim).child("Enter opens · q closes it · Esc")))
      .child(h_flex().h(36).flex_none().px(10).items_center().rounded(9).border_1().border_color(t.accent).bg(t.background)
        .child(Input.new(this.input).flex_1().h_full().text_size(12.8).text_color(t.foreground)))
      .when(Boolean(status), (el) => el.child(div().px(10).py(6).text_color(t.muted).child(status)))
      // The popup sizes to its content, so the list needs a real height.
      .child(v_flex().id("fv-list").h(Math.min(rows.length * 32, 420)).flex_none().min_h(0).overflow_y_scrollbar().gap(2).children(
        rows.map((item, i) => {
          const [dir, base] = name(item.label);
          const on = i === this.at;
          return h_flex().id(`fv-${i}`).h(30).flex_none().px(10).gap(0).items_center().rounded(7).cursor_pointer()
            .bg(on ? t.selected : t.popover).hover((s) => s.bg(on ? t.selected : t.hover))
            .on_click(() => this.open(item))
            .child(div().min_w(0).flex_shrink(1).truncate().text_color(t.dim).child(dir))
            .child(div().flex_none().text_color(on ? t.foreground : t.muted).child(base));
        })));
  }
}
