import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from pnpm_dependency_graph import snapshot  # noqa: E402

# Shaped like pnpm 12's lockfile: a first document that only pins pnpm, then
# the workspace's lockfile.
PNPM_DOC = {
    "lockfileVersion": "9.0",
    "importers": {".": {"packageManagerDependencies": {"pnpm": {"specifier": "12.3.4", "version": "12.3.4"}}}},
    "packages": {"pnpm@12.3.4": {}},
}
LOCK_DOC = {
    "lockfileVersion": "9.0",
    "importers": {
        ".": {"devDependencies": {"vitest": {"specifier": "catalog:testing", "version": "5.0.0"}}},
        "apps/web": {
            "dependencies": {
                "react": {"specifier": "catalog:react", "version": "19.2.4"},
                "@acme/ui": {"specifier": "workspace:*", "version": "link:../../packages/ui"},
                "string-width-cjs": {"specifier": "npm:string-width@^4", "version": "string-width@4.2.3"},
            },
            "devDependencies": {"@testing-library/jest-dom": {"specifier": "^7", "version": "7.0.1(vitest@5.0.0)"}},
        },
        "packages/ui": {"dependencies": {"clsx": {"specifier": "^2", "version": "2.1.1"}}},
    },
    "packages": {
        "react@19.2.4": {},
        "loose-envify@1.4.0": {},
        "vitest@5.0.0": {},
        "tinyspy@4.0.0": {},
        "@testing-library/jest-dom@7.0.1": {"peerDependencies": {"vitest": "*"}},
        "string-width@4.2.3": {},
        "clsx@2.1.1": {},
    },
    "snapshots": {
        "react@19.2.4": {"dependencies": {"loose-envify": "1.4.0"}},
        "loose-envify@1.4.0": {},
        "vitest@5.0.0": {"dependencies": {"tinyspy": "4.0.0"}},
        "tinyspy@4.0.0": {},
        "@testing-library/jest-dom@7.0.1(vitest@5.0.0)": {"optionalDependencies": {"vitest": "5.0.0"}},
        "string-width@4.2.3": {},
        "clsx@2.1.1": {},
    },
}


def resolved(snap, manifest):
    return {p: (r["scope"], r["relationship"]) for p, r in snap["manifests"][manifest]["resolved"].items()}


class SnapshotTest(unittest.TestCase):
    def setUp(self):
        self.snap = snapshot([PNPM_DOC, LOCK_DOC])

    def test_one_manifest_per_workspace_package_json(self):
        self.assertEqual(set(self.snap["manifests"]), {"package.json", "apps/web/package.json", "packages/ui/package.json"})
        self.assertEqual(self.snap["job"]["correlator"], "pnpm-dependency-submission")

    def test_resolves_versions_transitives_and_aliases(self):
        self.assertEqual(resolved(self.snap, "apps/web/package.json"), {
            "pkg:npm/react@19.2.4": ("runtime", "direct"),
            "pkg:npm/loose-envify@1.4.0": ("runtime", "indirect"),
            "pkg:npm/string-width@4.2.3": ("runtime", "direct"),
            "pkg:npm/%40testing-library/jest-dom@7.0.1": ("development", "direct"),
            # Reached only as jest-dom's peer, which apps/web doesn't declare
            # itself: development, like the root's direct vitest.
            "pkg:npm/vitest@5.0.0": ("development", "indirect"),
            "pkg:npm/tinyspy@4.0.0": ("development", "indirect"),
        })

    def test_workspace_links_are_not_packages(self):
        purls = {p for m in self.snap["manifests"].values() for p in m["resolved"]}
        self.assertFalse(any("acme" in p or "link:" in p for p in purls))
        self.assertEqual(resolved(self.snap, "packages/ui/package.json"), {"pkg:npm/clsx@2.1.1": ("runtime", "direct")})

    def test_a_peer_does_not_make_a_package_runtime(self):
        doc = dict(LOCK_DOC, importers={"apps/web": {"dependencies": {
            "@testing-library/jest-dom": {"specifier": "^7", "version": "7.0.1(vitest@5.0.0)"}}}})
        got = resolved(snapshot([doc]), "apps/web/package.json")
        self.assertEqual(got["pkg:npm/%40testing-library/jest-dom@7.0.1"], ("runtime", "direct"))
        self.assertEqual(got["pkg:npm/vitest@5.0.0"], ("runtime", "indirect"), "reachable only through the peer, so it takes the scope of what reaches it")

    def test_lockfile_in_a_subdirectory(self):
        self.assertIn("frontend/apps/web/package.json", snapshot([LOCK_DOC], "frontend")["manifests"])


if __name__ == "__main__":
    unittest.main()
