#!/usr/bin/env python3
"""Mecánica de release del marketplace agentic-toolbox.

Sincroniza las versiones (plugin.json de cada plugin, marketplace.json),
rueda el CHANGELOG ([Unreleased] -> [X.Y.Z] - fecha, enlaces de comparación),
crea el commit chore(release), el tag anotado vX.Y.Z y hace push atómico de
commit + tag. La redacción de la entrada del CHANGELOG y la decisión del bump
son juicio humano/skill: este script solo valida y ejecuta.

Uso:
  release.py check
  release.py run --version X.Y.Z [--plugin nombre=X.Y.Z]... [--dry-run] [--no-push]
"""

import argparse
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
MARKETPLACE = REPO / ".claude-plugin" / "marketplace.json"
CHANGELOG = REPO / "CHANGELOG.md"
PLUGINS_DIR = REPO / "plugins"
COMPARE_BASE = "https://github.com/540/agentic-toolbox"


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def git(*args, check=True):
    result = subprocess.run(
        ["git", "-C", str(REPO), *args], capture_output=True, text=True
    )
    if check and result.returncode != 0:
        die(f"git {' '.join(args)} falló:\n{result.stderr.strip()}")
    return result.stdout.strip()


def parse_semver(version):
    m = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", version)
    if not m:
        die(f"versión inválida (se espera X.Y.Z): {version}")
    return tuple(int(x) for x in m.groups())


def plugin_json_path(name):
    return PLUGINS_DIR / name / ".claude-plugin" / "plugin.json"


def read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def changelog_versions(text):
    """Versiones publicadas en el CHANGELOG, en orden de aparición."""
    return re.findall(r"^## \[(\d+\.\d+\.\d+)\] - \d{4}-\d{2}-\d{2}$", text, re.M)


def unreleased_body(text):
    """Contenido entre ## [Unreleased] y la siguiente sección ##."""
    m = re.search(r"^## \[Unreleased\]\n(.*?)(?=^## )", text, re.M | re.S)
    if not m:
        die("el CHANGELOG no tiene sección '## [Unreleased]'")
    return m.group(1)


def local_tags():
    out = git("tag", "-l", "v*")
    return set(out.splitlines()) if out else set()


def remote_tags():
    out = git("ls-remote", "--tags", "origin")
    return {
        line.split("refs/tags/")[1].removesuffix("^{}")
        for line in out.splitlines()
        if "refs/tags/" in line
    }


def gather_state():
    marketplace = read_json(MARKETPLACE)
    plugins = {
        p["name"]: {
            "marketplace_version": p["version"],
            "plugin_json_version": read_json(plugin_json_path(p["name"]))["version"],
        }
        for p in marketplace["plugins"]
    }
    changelog = CHANGELOG.read_text(encoding="utf-8")
    versions = changelog_versions(changelog)
    return {
        "marketplace_version": marketplace["metadata"]["version"],
        "plugins": plugins,
        "changelog_latest": versions[0] if versions else None,
        "changelog_text": changelog,
    }


def consistency_errors(state):
    errors = []
    if state["marketplace_version"] != state["changelog_latest"]:
        errors.append(
            f"marketplace metadata.version ({state['marketplace_version']}) != "
            f"última versión del CHANGELOG ({state['changelog_latest']})"
        )
    for name, v in state["plugins"].items():
        if v["marketplace_version"] != v["plugin_json_version"]:
            errors.append(
                f"plugin '{name}': marketplace.json dice {v['marketplace_version']} "
                f"pero plugin.json dice {v['plugin_json_version']}"
            )
    return errors


def cmd_check(_args):
    git("fetch", "origin")
    state = gather_state()
    locals_, remotes = local_tags(), remote_tags()
    unpushed = sorted(locals_ - remotes)
    latest_tag = git("describe", "--tags", "--abbrev=0", check=False) or "(ninguno)"

    print(f"Marketplace (metadata.version): {state['marketplace_version']}")
    for name, v in state["plugins"].items():
        print(
            f"  plugin {name}: plugin.json={v['plugin_json_version']} "
            f"marketplace.json={v['marketplace_version']}"
        )
    print(f"CHANGELOG última versión: {state['changelog_latest']}")
    print(f"Último tag local: {latest_tag}")
    print(f"Tags locales sin pushear: {unpushed or 'ninguno'}")

    dirty = git("status", "--porcelain")
    print(f"Working tree: {'limpio' if not dirty else 'SUCIO'}")
    if dirty:
        print(dirty)

    if latest_tag != "(ninguno)":
        print(f"\nCommits desde {latest_tag}:")
        log = git("log", "--oneline", f"{latest_tag}..HEAD")
        print(log or "  (ninguno)")
        for name in state["plugins"]:
            plog = git("log", "--oneline", f"{latest_tag}..HEAD", "--", f"plugins/{name}")
            if plog:
                print(f"  [{name}]")
                for line in plog.splitlines():
                    print(f"    {line}")

    errors = consistency_errors(state)
    expected_tag = f"v{state['marketplace_version']}"
    if expected_tag not in locals_:
        errors.append(f"falta el tag {expected_tag} de la versión ya publicada")
    if unpushed:
        errors.append(
            f"tags sin pushear: {', '.join(unpushed)} "
            f"(reparar: git push origin {' '.join(unpushed)})"
        )
    if errors:
        print("\nDESINCRONIZACIÓN detectada:")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    print("\nOK: estado coherente.")


def validate_run(args, state):
    branch = git("branch", "--show-current")
    if branch != "main":
        die(f"hay que estar en main (rama actual: {branch})")
    git("fetch", "origin")
    if git("rev-parse", "HEAD") != git("rev-parse", "origin/main"):
        die("HEAD != origin/main: pushea (o trae) los commits de contenido antes del release")

    dirty = [l for l in git("status", "--porcelain").splitlines() if l.strip()]
    untracked = [l for l in dirty if l.startswith("??")]
    tracked = [l for l in dirty if not l.startswith("??")]
    allowed = {"M CHANGELOG.md", "M  CHANGELOG.md"}
    if any(l.strip() not in allowed for l in tracked):
        die(
            "working tree sucio (solo se permite CHANGELOG.md modificado):\n"
            + "\n".join(tracked)
        )
    if untracked:
        print("AVISO: ficheros sin trackear (no entran en el release):")
        for l in untracked:
            print(f"  {l}")

    errors = consistency_errors(state)
    if errors:
        die("versiones desincronizadas; ejecuta 'check' y repara:\n  " + "\n  ".join(errors))

    new = parse_semver(args.version)
    current = parse_semver(state["marketplace_version"])
    if new <= current:
        die(f"--version {args.version} debe ser mayor que la actual {state['marketplace_version']}")

    for name, version in args.plugins.items():
        if name not in state["plugins"]:
            die(f"plugin desconocido: {name} (existen: {', '.join(state['plugins'])})")
        if parse_semver(version) <= parse_semver(state["plugins"][name]["plugin_json_version"]):
            die(
                f"plugin {name}: {version} debe ser mayor que la actual "
                f"{state['plugins'][name]['plugin_json_version']}"
            )

    tag = f"v{args.version}"
    if tag in local_tags():
        die(f"el tag {tag} ya existe en local")
    if tag in remote_tags():
        die(f"el tag {tag} ya existe en origin")
    unpushed = sorted(local_tags() - remote_tags())
    if unpushed:
        die(
            f"tags locales sin pushear: {', '.join(unpushed)} "
            f"(reparar: git push origin {' '.join(unpushed)})"
        )

    body = unreleased_body(state["changelog_text"])
    if not re.search(r"^- ", body, re.M):
        die("[Unreleased] está vacío: escribe la entrada del changelog antes del release")


def roll_changelog(text, version, today):
    """[Unreleased] pasa su contenido a [X.Y.Z] - fecha y regenera los enlaces."""
    body = unreleased_body(text)
    text = text.replace(
        f"## [Unreleased]\n{body}",
        f"## [Unreleased]\n\n## [{version}] - {today}\n{body}",
        1,
    )
    previous = changelog_versions(text)[1]  # la que era latest antes de insertar
    old_link = re.search(r"^\[Unreleased\]: \S+$", text, re.M)
    if not old_link:
        die("el CHANGELOG no tiene enlace [Unreleased] al pie")
    text = text.replace(
        old_link.group(0),
        f"[Unreleased]: {COMPARE_BASE}/compare/v{version}...HEAD\n"
        f"[{version}]: {COMPARE_BASE}/compare/v{previous}...v{version}",
        1,
    )
    return text


def cmd_run(args):
    state = gather_state()
    validate_run(args, state)
    tag = f"v{args.version}"
    today = date.today().isoformat()

    print("Plan de release:")
    print(f"  marketplace: {state['marketplace_version']} -> {args.version}")
    for name, version in args.plugins.items():
        print(f"  plugin {name}: {state['plugins'][name]['plugin_json_version']} -> {version}")
    print(f"  CHANGELOG: [Unreleased] -> [{args.version}] - {today}")
    print(f"  commit: chore(release): {tag}")
    print(f"  tag anotado: {tag}")
    print(f"  push: {'NO (--no-push)' if args.no_push else f'git push --atomic origin main {tag}'}")

    if args.dry_run:
        print("\n--dry-run: no se ha modificado nada.")
        return

    marketplace = read_json(MARKETPLACE)
    marketplace["metadata"]["version"] = args.version
    for entry in marketplace["plugins"]:
        if entry["name"] in args.plugins:
            entry["version"] = args.plugins[entry["name"]]
    write_json(MARKETPLACE, marketplace)

    for name, version in args.plugins.items():
        path = plugin_json_path(name)
        data = read_json(path)
        data["version"] = version
        write_json(path, data)

    CHANGELOG.write_text(
        roll_changelog(state["changelog_text"], args.version, today), encoding="utf-8"
    )

    files = ["CHANGELOG.md", str(MARKETPLACE.relative_to(REPO))] + [
        str(plugin_json_path(n).relative_to(REPO)) for n in args.plugins
    ]
    git("add", *files)
    git("commit", "-m", f"chore(release): {tag}")
    git("tag", "-a", tag, "-m", f"agentic-toolbox {tag}")
    print(f"\nCommit y tag {tag} creados.")

    if args.no_push:
        print(f"Pendiente: git push --atomic origin main {tag}")
        return

    result = subprocess.run(
        ["git", "-C", str(REPO), "push", "--atomic", "origin", "main", tag],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        die(
            "el push falló. El commit y el tag existen en local; "
            f"recuperación: git push --atomic origin main {tag}"
        )
    print(f"Publicado: {COMPARE_BASE}/compare/v{state['marketplace_version']}...{tag}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check", help="diagnóstico de coherencia, solo lectura")
    run = sub.add_parser("run", help="ejecutar el release")
    run.add_argument("--version", required=True, help="nueva versión del marketplace X.Y.Z")
    run.add_argument(
        "--plugin",
        action="append",
        default=[],
        metavar="nombre=X.Y.Z",
        help="plugin a bumpear (repetible); sin --plugin solo bumpea el marketplace",
    )
    run.add_argument("--dry-run", action="store_true", help="validar y mostrar el plan sin mutar")
    run.add_argument("--no-push", action="store_true", help="todo menos el push")
    args = parser.parse_args()

    if args.command == "check":
        cmd_check(args)
    else:
        plugins = {}
        for spec in args.plugin:
            if "=" not in spec:
                die(f"--plugin espera nombre=X.Y.Z, recibido: {spec}")
            name, _, version = spec.partition("=")
            parse_semver(version)
            plugins[name] = version
        args.plugins = plugins
        cmd_run(args)


if __name__ == "__main__":
    main()
