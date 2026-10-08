import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
TAG = "v1.0.0-2"
PACKAGE_NAMES = {
    "deb": "okular-session_1.0.0-2_all.deb",
    "arch": "okular-session-1.0.0-2-any.pkg.tar.zst",
}

# Command boundaries emulate a download server, package managers, and GitHub.
# Tests assert verified payloads and release state rather than command ordering.
FAKE_COMMAND = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import sys

root = Path(os.environ["DISTRIBUTION_FIXTURE"])
command = Path(sys.argv[0]).name
args = sys.argv[1:]
if command == "sudo":
    os.execvp(args[0], args)
elif command == "curl":
    if args[-1].endswith("/latest"):
        print("https://github.com/AkiraLyu/Okular-session/releases/tag/v1.0.0-2", end="")
    else:
        source = root / "downloads" / args[-1].rsplit("/", 1)[-1]
        if not source.is_file():
            sys.exit(22)
        shutil.copyfile(source, args[args.index("--output") + 1])
elif command in ("apt-get", "pacman"):
    package = Path(args[-1])
    (root / "installed.json").write_text(json.dumps({
        "manager": command, "name": package.name,
        "payload": package.read_text(),
    }))
elif command == "gh":
    state_path = root / "release.json"
    if args[:2] == ["release", "create"]:
        if state_path.exists():
            sys.exit("release already exists")
        assets = {}
        for item in args[3:args.index("--draft")]:
            assets[Path(item).name] = Path(item).read_text()
        state_path.write_text(json.dumps({"draft": True, "assets": assets}))
        if (root / "upload-fails").exists():
            sys.exit("upload failed")
    elif args[:2] == ["release", "edit"]:
        state = json.loads(state_path.read_text())
        state["draft"] = False
        state_path.write_text(json.dumps(state))
    else:
        sys.exit("unsupported release operation")
else:
    sys.exit("unsupported command")
'''


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="okular-distribution-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        commands = self.root / "bin"
        commands.mkdir()
        for name in ("curl", "apt-get", "pacman", "sudo", "gh"):
            executable = commands / name
            executable.write_text(FAKE_COMMAND)
            executable.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{commands}:{os.environ['PATH']}",
                        DISTRIBUTION_FIXTURE=str(self.root))
        self.downloads = self.root / "downloads"
        self.downloads.mkdir()
        for name in PACKAGE_NAMES.values():
            (self.downloads / name).write_text("verified package payload\n")
        self.manifest = "".join(
            f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n"
            for path in sorted(self.downloads.iterdir())
        )
        (self.downloads / "SHA256SUMS").write_text(self.manifest)

    def run_script(self, name, *args):
        return subprocess.run(["bash", str(REPOSITORY / name), *args],
                              env=self.env, capture_output=True, text=True)

    def test_installer_selects_revision_for_both_formats(self):
        for fmt, name in PACKAGE_NAMES.items():
            with self.subTest(format=fmt):
                result = self.run_script("install.sh", "--package", fmt, "--yes")
                self.assertEqual(result.returncode, 0, result.stderr)
                installed = json.loads((self.root / "installed.json").read_text())
                self.assertEqual(installed["manager"], {"deb": "apt-get", "arch": "pacman"}[fmt])
                self.assertEqual(installed["name"], name)
                self.assertEqual(installed["payload"], "verified package payload\n")

    def test_corrupt_payload_is_not_installed(self):
        (self.downloads / PACKAGE_NAMES["deb"]).write_text("corrupted")
        result = self.run_script("install.sh", "--package", "deb", "--version", TAG)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "installed.json").exists())

    def test_missing_or_ambiguous_package_is_not_installed(self):
        for manifest in ("", self.manifest + self.manifest):
            with self.subTest(manifest=manifest):
                (self.downloads / "SHA256SUMS").write_text(manifest)
                result = self.run_script("install.sh", "--package", "arch", "--version", TAG)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.root / "installed.json").exists())

    def prepare_assets(self):
        assets = self.root / "assets"
        assets.mkdir()
        for name in (*PACKAGE_NAMES.values(), "okular-session-1.0.0-2.tar.gz", "PKGBUILD", "install.sh"):
            (assets / name).write_text(f"contents of {name}\n")
        return assets

    def test_existing_release_is_unchanged(self):
        assets = self.prepare_assets()
        state_path = self.root / "release.json"
        for draft in (False, True):
            with self.subTest(draft=draft):
                state = {"draft": draft, "assets": {"existing.deb": "original content"}}
                state_path.write_text(json.dumps(state))
                result = self.run_script("packaging/publish.sh", TAG, str(assets))
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(json.loads(state_path.read_text()), state)

    def test_upload_failure_leaves_release_in_draft(self):
        assets = self.prepare_assets()
        (self.root / "upload-fails").touch()
        result = self.run_script("packaging/publish.sh", TAG, str(assets))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(json.loads((self.root / "release.json").read_text())["draft"])

    def test_missing_asset_creates_no_release(self):
        assets = self.prepare_assets()
        (assets / "PKGBUILD").unlink()
        result = self.run_script("packaging/publish.sh", TAG, str(assets))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "release.json").exists())

    def test_complete_release_has_matching_checksums(self):
        assets = self.prepare_assets()
        result = self.run_script("packaging/publish.sh", TAG, str(assets))
        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads((self.root / "release.json").read_text())
        self.assertFalse(state["draft"])
        for line in state["assets"]["SHA256SUMS"].splitlines():
            digest, name = line.split()
            self.assertEqual(hashlib.sha256(state["assets"][name].encode()).hexdigest(), digest)


if __name__ == "__main__":
    unittest.main()
