"""Turns a pnpm-lock.yaml, converted to JSON documents by yq, into a GitHub
dependency graph snapshot.

usage: yq -o=json -I=0 '.' <dir>/pnpm-lock.yaml | python3 pnpm_dependency_graph.py <dir>

Every workspace package (importer) is a root. A package reachable from any
importer's dependencies or optionalDependencies is runtime; one reachable only
from devDependencies is development, as npm and GitHub scope them. Peer
dependencies don't decide a package's scope, since the consumer supplies them.
Workspace links (link:) aren't packages.
"""

import json
import os
import sys
from datetime import datetime, timezone
from urllib.parse import quote


def base_version(version):
    """The version without pnpm's peer suffix: 5.2.1(supports-color@8.1.1) is 5.2.1."""
    return version.split("(", 1)[0]


def snapshot_key(name, version):
    """The snapshots key a dependency points at. An alias's version names the
    target itself: string-width-cjs: string-width@4.2.3."""
    if "@" in base_version(version)[1:]:
        return version
    return f"{name}@{version}"


def split_key(key):
    """name and version of a snapshots key, scoped names included."""
    base = key.split("(", 1)[0]
    at = base.rindex("@")
    return base[:at], base[at + 1:]


def purl(key):
    name, version = split_key(key)
    return f"pkg:npm/{quote(name, safe='/')}@{quote(version, safe='')}"


def is_package(version):
    return not version.startswith(("link:", "file:", "workspace:"))


def snapshot(docs, lockfile_dir=""):
    snapshots, packages, importers = {}, {}, {}
    for doc in docs:
        snapshots.update(doc.get("snapshots") or {})
        packages.update(doc.get("packages") or {})
        importers.update(doc.get("importers") or {})

    runtime_kinds = ("dependencies", "optionalDependencies")
    kinds = (("dependencies", True), ("optionalDependencies", True), ("devDependencies", False))

    roots = {"runtime": set(), "development": set()}
    for path, importer in importers.items():
        for kind, runtime_kind in kinds:
            scope = "runtime" if runtime_kind else "development"
            for name, dep in (importer.get(kind) or {}).items():
                if is_package(dep["version"]):
                    roots[scope].add(snapshot_key(name, dep["version"]))

    def edges(key, peers):
        """The packages key depends on. Peer dependencies are supplied by the
        consumer, so they only count with peers=True."""
        entry = snapshots.get(key) or {}
        peer_names = set((packages.get("@".join(split_key(key))) or {}).get("peerDependencies") or {})
        for kind in runtime_kinds:
            for name, version in (entry.get(kind) or {}).items():
                if is_package(version) and (peers or name not in peer_names):
                    yield snapshot_key(name, version)

    def reachable(start, peers):
        seen, todo = set(), list(start)
        while todo:
            key = todo.pop()
            if key not in seen:
                seen.add(key)
                todo.extend(edges(key, peers))
        return seen

    # A package's scope follows what it's reachable from without peers; one
    # reachable only through a peer takes the scope of what reaches it.
    runtime = reachable(roots["runtime"], False)
    development = reachable(roots["development"], False) - runtime
    everything = reachable(roots["runtime"] | roots["development"], True)
    runtime |= reachable(runtime, True) & (everything - runtime - development)
    development |= everything - runtime - development
    # One manifest per workspace package, named after its package.json, so
    # it replaces what GitHub reads from that package.json itself: ranges
    # and catalog: specifiers, without the packages they pull in.
    runtime_purls = {purl(k) for k in runtime}
    manifests = {}
    for path, importer in importers.items():
        own = {snapshot_key(name, dep["version"]) for kind, _ in kinds
               for name, dep in (importer.get(kind) or {}).items() if is_package(dep["version"])}
        resolved = {}
        for key in reachable(own, True):
            p = purl(key)
            entry = resolved.setdefault(p, {
                "package_url": p,
                "relationship": "indirect",
                "scope": "runtime" if p in runtime_purls else "development",
                "dependencies": set(),
            })
            entry["dependencies"] |= {purl(k) for k in edges(key, True)}
            if key in own:
                entry["relationship"] = "direct"
        for entry in resolved.values():
            entry["dependencies"] = sorted(entry["dependencies"])
        manifest = os.path.normpath(os.path.join(lockfile_dir, path, "package.json"))
        manifests[manifest] = {"name": manifest, "file": {"source_location": manifest}, "resolved": resolved}

    return {
        "version": 0,
        "job": {
            "correlator": "pnpm-dependency-submission",
            "id": os.environ.get("GITHUB_RUN_ID", "local"),
        },
        "sha": os.environ.get("GITHUB_SHA", "0" * 40),
        "ref": os.environ.get("GITHUB_REF", "refs/heads/main"),
        "detector": {
            "name": "monta-pnpm-lock",
            "version": "1.0.0",
            "url": "https://github.com/monta-app/github-workflows",
        },
        "scanned": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "manifests": manifests,
    }


if __name__ == "__main__":
    docs = [json.loads(line) for line in sys.stdin if line.strip()]
    json.dump(snapshot(docs, sys.argv[1] if len(sys.argv) > 1 else ""), sys.stdout)
