#!/usr/bin/env python3
"""Audit `.cs3` plugin compatibility against the bundled CloudStream library.

Answers one question with evidence: do the plugins real repos ship reference any
class or method our native host does not provide? Class presence alone is not
enough — a plugin links by (owner, name, descriptor), so a method that is missing
fails with NoSuchMethodError at runtime even when every class resolves. This
walks the plugin jars' constant pools and resolves each reference against the
`library-android` AAR on the Gradle cache.

Usage:
    python3 tools/cs3_compat/audit.py --plugins-dir /tmp/plug
    python3 tools/cs3_compat/audit.py --fetch --limit-repos 5 --per-repo 4

--fetch downloads the community repo index and a sample of plugins into
--plugins-dir first (default: a temp dir), so the audit can run from a clean
checkout with no manual setup.

Exit code is 1 when anything is missing, so this can gate CI.
"""

from __future__ import annotations

import argparse
import collections
import glob
import json
import os
import struct
import sys
import tempfile
import urllib.request
import zipfile

REPOS_DB = "https://raw.githubusercontent.com/recloudstream/cs-repos/master/repos-db.json"

# Types that come from the JDK/Android/third-party deps rather than our host.
EXTERNAL_PREFIXES = (
    "java.", "javax.", "kotlin.", "kotlinx.", "android.", "androidx.",
    "okhttp3.", "com.fasterxml.", "org.", "dalvik.", "okio.", "com.google.",
    "com.uwetrottmann.", "dev.whyoleg.", "io.ktor.", "com.fleeksoft.",
    "com.github.",
)

# Packages we must be able to resolve; everything else is out of scope.
HOST_PREFIXES = ("com.lagradost.cloudstream3", "com.lagradost.nicehttp")


class ClassFile:
    """Just enough of a class file to answer link questions."""

    __slots__ = ("name", "super_name", "interfaces", "methods")

    def __init__(self):
        self.name = None
        self.super_name = None
        self.interfaces = []
        self.methods = set()


def parse_class(data: bytes):
    """Return (ClassFile, set of (owner, method, descriptor) references)."""
    if data[:4] != b"\xca\xfe\xba\xbe":
        return None, set()

    count = struct.unpack(">H", data[8:10])[0]
    i = 10
    idx = 1
    utf8: dict[int, str] = {}
    class_ref: dict[int, int] = {}
    name_and_type: dict[int, tuple[int, int]] = {}
    member_refs: list[tuple[int, int]] = []

    while idx < count:
        tag = data[i]
        i += 1
        if tag == 1:
            length = struct.unpack(">H", data[i:i + 2])[0]
            i += 2
            utf8[idx] = data[i:i + length].decode("utf-8", "replace")
            i += length
        elif tag == 7:
            class_ref[idx] = struct.unpack(">H", data[i:i + 2])[0]
            i += 2
        elif tag in (9, 10, 11):
            owner, nt = struct.unpack(">HH", data[i:i + 4])
            member_refs.append((owner, nt))
            i += 4
        elif tag == 12:
            name_and_type[idx] = struct.unpack(">HH", data[i:i + 4])
            i += 4
        elif tag in (8, 16, 19, 20):
            i += 2
        elif tag == 15:
            i += 3
        elif tag in (3, 4, 17, 18):
            i += 4
        elif tag in (5, 6):  # long/double occupy two constant-pool slots
            i += 8
            idx += 1
        else:
            raise ValueError(f"unexpected constant pool tag {tag}")
        idx += 1

    def class_name(ci: int):
        utf8_index = class_ref.get(ci)
        return utf8.get(utf8_index) if utf8_index else None

    _access, this_class, super_class = struct.unpack(">HHH", data[i:i + 6])
    i += 6

    cls = ClassFile()
    cls.name = class_name(this_class)
    cls.super_name = class_name(super_class)

    interface_count = struct.unpack(">H", data[i:i + 2])[0]
    i += 2
    for _ in range(interface_count):
        name = class_name(struct.unpack(">H", data[i:i + 2])[0])
        i += 2
        if name:
            cls.interfaces.append(name)

    for kind in ("fields", "methods"):
        member_count = struct.unpack(">H", data[i:i + 2])[0]
        i += 2
        for _ in range(member_count):
            _flags, name_i, desc_i, attr_count = struct.unpack(">HHHH", data[i:i + 8])
            i += 8
            if kind == "methods":
                cls.methods.add((utf8.get(name_i, ""), utf8.get(desc_i, "")))
            for _ in range(attr_count):
                i += 2  # attribute name index
                length = struct.unpack(">I", data[i:i + 4])[0]
                i += 4 + length

    refs = set()
    for owner_i, nt_i in member_refs:
        owner = class_name(owner_i)
        pair = name_and_type.get(nt_i)
        if not owner or not pair:
            continue
        name = utf8.get(pair[0])
        if name:
            refs.add((owner, name, utf8.get(pair[1], "")))
    return cls, refs


def load_jar(path: str):
    """Return (classes by name, all member references) for a jar."""
    classes: dict[str, ClassFile] = {}
    refs: set[tuple[str, str, str]] = set()
    with zipfile.ZipFile(path) as jar:
        for entry in jar.namelist():
            if not entry.endswith(".class"):
                continue
            try:
                cls, jar_refs = parse_class(jar.read(entry))
            except (ValueError, struct.error):
                continue  # skip anything unparsable rather than abort the audit
            if cls and cls.name:
                classes[cls.name] = cls
            refs |= jar_refs
    return classes, refs


def library_jar() -> str:
    """Extract classes.jar from the cached library-android AAR."""
    candidates = [
        os.path.expanduser(
            "~/.gradle/caches/modules-2/files-2.1/com.github.recloudstream.cloudstream"
            "/library-android/*/*/*.aar"
        ),
        "/workspace/toolchain/gradle/caches/modules-2/files-2.1/"
        "com.github.recloudstream.cloudstream/library-android/*/*/*.aar",
    ]
    aars = []
    for pattern in candidates:
        aars.extend(glob.glob(pattern))
    if not aars:
        sys.exit("library-android AAR not found; run a Gradle sync first")
    out = os.path.join(tempfile.gettempdir(), "cs3_audit_lib.jar")
    with zipfile.ZipFile(sorted(aars)[-1]) as aar:
        with open(out, "wb") as fh:
            fh.write(aar.read("classes.jar"))
    return out


def declares(classes, owner, name, desc, seen=None) -> bool:
    """Does owner (or a supertype) declare name/desc?"""
    if seen is None:
        seen = set()
    if owner in seen:
        return False
    seen.add(owner)
    cls = classes.get(owner)
    if cls is None:
        return False
    if (name, desc) in cls.methods or any(m[0] == name for m in cls.methods):
        return True
    if cls.super_name and declares(classes, cls.super_name, name, desc, seen):
        return True
    return any(declares(classes, i, name, desc, seen) for i in cls.interfaces)


def _request(url: str):
    return urllib.request.Request(url, headers={"User-Agent": "zangetsu-cs3-audit"})


def fetch_plugins(target: str, limit_repos: int, per_repo: int) -> None:
    os.makedirs(target, exist_ok=True)
    with urllib.request.urlopen(_request(REPOS_DB), timeout=30) as r:
        repos = json.loads(r.read())
    urls = [e if isinstance(e, str) else e["url"] for e in repos][:limit_repos]
    for repo_url in urls:
        try:
            with urllib.request.urlopen(_request(repo_url), timeout=25) as r:
                manifest = json.loads(r.read())
        except Exception:
            continue
        entries = []
        for list_url in manifest.get("pluginLists") or []:
            try:
                with urllib.request.urlopen(_request(list_url), timeout=25) as r:
                    for plugin in json.loads(r.read()):
                        jar = plugin.get("url") or plugin.get("jarUrl")
                        if jar:
                            entries.append((plugin.get("internalName", "plugin"), jar))
            except Exception:
                continue
        for name, jar_url in entries[:per_repo]:
            dest = os.path.join(target, f"{name}.jar")
            if os.path.exists(dest):
                continue
            try:
                with urllib.request.urlopen(_request(jar_url), timeout=30) as r:
                    with open(dest, "wb") as fh:
                        fh.write(r.read())
            except Exception:
                continue


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugins-dir", help="directory of plugin jars")
    parser.add_argument("--fetch", action="store_true", help="download a plugin sample first")
    parser.add_argument("--limit-repos", type=int, default=38)
    parser.add_argument("--per-repo", type=int, default=4)
    args = parser.parse_args()

    plugins_dir = args.plugins_dir
    if args.fetch:
        plugins_dir = plugins_dir or tempfile.mkdtemp(prefix="cs3-plugins-")
        fetch_plugins(plugins_dir, args.limit_repos, args.per_repo)
    if not plugins_dir:
        parser.error("--plugins-dir is required unless --fetch is given")

    lib_classes, _ = load_jar(library_jar())
    missing_classes = collections.Counter()
    missing_methods = collections.Counter()
    audited = 0

    for jar in sorted(glob.glob(os.path.join(plugins_dir, "*.jar"))):
        try:
            plugin_classes, refs = load_jar(jar)
        except zipfile.BadZipFile:
            continue
        audited += 1
        for owner, name, desc in refs:
            if not owner.startswith(HOST_PREFIXES) or owner.startswith("["):
                continue
            if owner in plugin_classes:
                continue
            if owner not in lib_classes:
                if not owner.startswith(EXTERNAL_PREFIXES):
                    missing_classes[owner] += 1
                continue
            if not declares(lib_classes, owner, name, desc):
                missing_methods[(owner, name, desc)] += 1

    print(f"plugins audited: {audited}")
    print(f"missing classes: {len(missing_classes)}")
    for owner, n in missing_classes.most_common(20):
        print(f"  {n:4d}  {owner}")
    print(f"missing methods: {len(missing_methods)}")
    for (owner, name, desc), n in missing_methods.most_common(20):
        print(f"  {n:4d}  {owner.split('.')[-1]}.{name}{desc}")

    if not audited:
        print("nothing audited — check --plugins-dir / --fetch", file=sys.stderr)
        return 2
    return 1 if (missing_classes or missing_methods) else 0


if __name__ == "__main__":
    sys.exit(main())
