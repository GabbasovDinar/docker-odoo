#!/usr/bin/env python3

from __future__ import annotations
import argparse
import os
import re
import sys
import stat

# ${NAME}, ${NAME:-def}, ${NAME-def}, ${NAME?:msg}
PH = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(:-|-|\?:)([^}]*))?\}")


def cli_args():
    default_env = os.environ.get("ODOO_ENV_FILE", "/run/odoo/.env")
    default_template = os.environ.get(
        "ODOO_RC_TEMPLATE", "/usr/local/share/odoo/tmpl/odoo.conf.tpl"
    )
    default_out = os.environ.get("ODOO_RC", "/etc/odoo.conf")

    p = argparse.ArgumentParser()
    p.add_argument(
        "--env",
        "-e",
        default=default_env,
        help="Path to .env file (default: ODOO_ENV_FILE)",
    )
    p.add_argument(
        "--template",
        "-t",
        default=default_template,
        help="Path to odoo.conf template (default: ODOO_RC_TEMPLATE)",
    )
    p.add_argument(
        "--out", "-o", default=default_out, help="Output config path (default: ODOO_RC)"
    )
    p.add_argument("--max-passes", type=int, default=5)
    p.add_argument(
        "--drop-unresolved",
        action="store_true",
        help="drop lines that still contain ${...} after rendering",
    )
    p.add_argument(
        "--drop-empty",
        action="store_true",
        default=True,
        help='drop lines that end up as "key =" (empty value)',
    )
    p.add_argument(
        "--treat-empty-unset",
        action="store_true",
        default=True,
        help="empty values in .env are treated as UNSET (removed)",
    )
    p.add_argument(
        "--strict",
        action="store_true",
        help="fail if any ${...} or ${...?...} remain after rendering",
    )
    return p.parse_args()


def read_text(path):
    with open(path, "r", encoding="utf-8") as f:
        s = f.read()
    return s.lstrip("\ufeff")


def write_text(path, data):
    with open(path, "w", encoding="utf-8") as f:
        f.write(data)
    os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)


def _store_env(out, key, value, *, treat_empty_unset):
    # Normalize CRs and strip only trailing \r
    v = value.replace("\r", "")
    # Treat empty/whitespace-only as UNSET if flag enabled
    if treat_empty_unset and (v.strip() == ""):
        return
    out[key] = v


def parse_env(path, *, treat_empty_unset):
    if not os.path.exists(path):
        return {}
    lines = read_text(path).splitlines()
    out = {}
    i = 0
    while i < len(lines):
        raw = lines[i]
        i += 1
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        if "=" not in line:
            # line like "FOO" without "=" -> ignore
            continue

        k, v = line.split("=", 1)
        k = k.strip()
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k):
            continue

        v = v.rstrip("\r")

        # double-quoted: allow multiline and escapes (\n, \t, \")
        if v.startswith('"'):
            buf = v[1:]
            while True:
                if buf.endswith('"') and not buf.endswith('\\"'):
                    buf = buf[:-1]
                    break
                if i >= len(lines):
                    break
                buf += "\n" + lines[i]
                i += 1
            try:
                buf = bytes(buf, "utf-8").decode("unicode_escape")
            except Exception:
                pass
            _store_env(out, k, buf, treat_empty_unset=treat_empty_unset)
            continue

        # single-quoted: literal (no escape interpretation)
        if v.startswith("'"):
            buf = v[1:]
            while True:
                if buf.endswith("'") and not buf.endswith("\\'"):
                    buf = buf[:-1]
                    break
                if i >= len(lines):
                    break
                buf += "\n" + lines[i]
                i += 1
            _store_env(out, k, buf, treat_empty_unset=treat_empty_unset)
            continue

        # unquoted: strip trailing " # comment"
        v = re.split(r"\s+#", v, 1)[0].strip()
        _store_env(out, k, v, treat_empty_unset=treat_empty_unset)

    return out


def sub_once(s, env):
    def repl(m):
        name, op, default = m.group(1), m.group(2), m.group(3)
        present = name in env
        val = env.get(name)

        if op == "?:":  # required
            if (not present) or (val is None or val == ""):
                # keep marker to signal error or be dropped later
                return f"${{{name}?{default or 'required'}}}"
            return str(val)

        if op == ":-":  # default if UNSET or EMPTY
            if (not present) or (val is None or val == ""):
                return default or ""
            return str(val)

        if op == "-":  # default if UNSET only
            if not present:
                return default or ""
            return "" if val is None else str(val)

        # plain ${VAR}: keep unresolved as ${...} for later dropping if needed
        return m.group(0) if (not present or val is None) else str(val)

    return PH.sub(repl, s)


def render(tpl, env, passes):
    prev, cur, n = None, tpl, 0
    while cur != prev and n < passes:
        prev, cur, n = cur, sub_once(cur, env), n + 1
    return cur


def postprocess(text, *, drop_unresolved, drop_empty):
    out_lines = []
    for line in text.splitlines():
        # 1) Drop lines that still contain ${...}
        if drop_unresolved and PH.search(line):
            continue

        if drop_empty:
            # Skip pure empty assignments, but keep comments/section headers
            # Examples removed: "foo =", "  foo=   "
            if not line.strip():
                # keep blank lines as-is (optional)
                out_lines.append(line)
                continue
            # ignore comments and section headers ; # [
            first = line.lstrip()[:1]
            if first in (";", "#", "["):
                out_lines.append(line)
                continue
            if "=" in line:
                key, val = line.split("=", 1)
                if val.strip() == "":
                    # drop "key ="
                    continue

        out_lines.append(line)

    return "\n".join(out_lines) + "\n"


def _ensure_enterprise_addons(env):
    """Append ODOO_EE_ADDONS_DIR to ADDONS_PATH if ODOO_EDITION=ee."""
    edition = (env.get("ODOO_EDITION") or env.get("odoo_edition") or "ce").lower()
    if edition != "ee":
        return
    ent = env.get("ODOO_EE_ADDONS_DIR", "/opt/enterprise-addons")
    if not ent:
        return
    # read existing path (ADDONS_PATH preferred; fallback to addons_path)
    cur = env.get("ADDONS_PATH") or env.get("addons_path") or ""
    parts = [p.strip() for p in cur.split(",") if p.strip()]
    if ent not in parts:
        parts.append(ent)
    env["ADDONS_PATH"] = ",".join(parts) if parts else ent


def main():
    a = cli_args()

    env = parse_env(a.env, treat_empty_unset=a.treat_empty_unset)
    env.update(os.environ)

    # EE handling: ensure enterprise path is in ADDONS_PATH when needed
    _ensure_enterprise_addons(env)

    tpl = read_text(a.template)
    rendered = render(tpl, env, a.max_passes)
    rendered = postprocess(
        rendered,
        drop_unresolved=a.drop_unresolved,
        drop_empty=a.drop_empty,
    )

    if a.strict:
        # Fail if any placeholders or required markers remain
        if PH.search(rendered) or re.search(r"\$\{\w+\?.*?\}", rendered):
            sys.stderr.write("Error: unresolved or required placeholders remain\n")
            return 2

    write_text(a.out, rendered)
    print(f"Generated: {a.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
