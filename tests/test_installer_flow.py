"""Offline behavior checks; no real installer or user's configuration is run."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFINITIONS = (ROOT / "install-codex-unix.sh").read_text().rsplit(
    '\nmain "$@"', maxsplit=1
)[0]


class UnixInstallerFlowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.home = self.base / "home"
        self.home.mkdir()
        self.environment = {
            key: value for key, value in os.environ.items()
            if not key.startswith("CODEX_")
        }
        self.environment.update({
            "HOME": str(self.home),
            "TMPDIR": str(self.base),
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "CODEX_INSTALL_DIR": str(self.bin),
            "FAKE_VERSION_OUTPUT": "codex-cli 0.164.0",
            "FAKE_VERSION_EXIT": "0",
        })
        codex = self.bin / "codex"
        codex.write_text(
            '#!/bin/sh\nif [ "$1" = "--version" ]; then\n'
            '  printf "%s\\n" "$FAKE_VERSION_OUTPUT"\n'
            '  exit "$FAKE_VERSION_EXIT"\nfi\nexit 0\n'
        )
        codex.chmod(0o755)

    def run_harness(self, body: str, **overrides: str) -> subprocess.CompletedProcess:
        harness = self.base / "harness.sh"
        harness.write_text(DEFINITIONS + "\n" + body + "\n")
        return subprocess.run(
            ["bash", str(harness)], env={**self.environment, **overrides},
            text=True, capture_output=True, timeout=15, check=False,
        )

    def test_version_output_requires_one_codex_cli_version_for_latest(self) -> None:
        for output in (
            "", "not a Codex version", "some-other-cli 0.164.0",
            "codex-cli 0.164.0 extra", "codex-cli 0.164.0\ncodex-cli 0.165.0",
            "codex-cli 0.164.0\ncodex-cli 0.164.0",
        ):
            with self.subTest(output=output):
                result = self.run_harness("verify_codex", FAKE_VERSION_OUTPUT=output)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertNotIn("codex doctor 检查完成", result.stdout)

    def test_valid_versions_and_exact_pins(self) -> None:
        for release, output, success in (
            ("latest", "codex-cli 0.164.0", True),
            ("latest", "warning: PATH notice\ncodex-cli 0.164.0", True),
            ("0.164.0", "codex-cli 0.164.0", True),
            ("0.164.0-alpha.1", "codex-cli 0.164.0-alpha.1", True),
            ("0.164.0", "codex-cli 0.164.0-alpha.1", False),
            ("0.164.0", "codex-cli 0.164.01", False),
            ("0.164.0", "warning: requested 0.164.0\ncodex-cli 0.163.0", False),
        ):
            with self.subTest(release=release, output=output):
                result = self.run_harness(
                    "verify_codex", CODEX_RELEASE=release, FAKE_VERSION_OUTPUT=output,
                )
                self.assertEqual(result.returncode == 0, success, result.stderr)
                self.assertNotIn("unbound variable", result.stderr)
                if not success:
                    self.assertIn("请求版本不一致", result.stderr)

    def test_nonzero_version_exit_is_rejected(self) -> None:
        result = self.run_harness("verify_codex", FAKE_VERSION_EXIT="1")
        self.assertNotEqual(result.returncode, 0)

    def test_path_conflict_rejects_other_install(self) -> None:
        other_bin = self.base / "other"
        other_bin.mkdir()
        other = other_bin / "codex"
        other.write_text('#!/bin/sh\necho "codex-cli 0.164.0"\n')
        other.chmod(0o755)
        result = self.run_harness(
            "verify_codex", PATH=f"{other_bin}{os.pathsep}{self.environment['PATH']}",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PATH 优先解析到其他 Codex", result.stderr)

    def test_required_linux_app_fails_readonly_preflight(self) -> None:
        for distro, version in (("alpine", "3.22"), ("arch", "rolling")):
            with self.subTest(distro=distro):
                result = subprocess.run(
                    ["bash", str(ROOT / "install-codex-linux.sh"),
                     "--check-only", "--require-app", "--non-interactive"],
                    env={**self.environment, "CODEX_TEST_UNAME_S": "Linux",
                         "CODEX_TEST_ARCH": "x64", "CODEX_TEST_LINUX_ID": distro,
                         "CODEX_TEST_LINUX_VERSION_ID": version},
                    text=True, capture_output=True, check=False, timeout=15,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("--require-app 无法完成", result.stderr)
                self.assertEqual(list(self.home.iterdir()), [])
                self.assertEqual(list(self.base.glob("codex-installer.*")), [])

    def test_optional_arch_plan_explains_manual_system_upgrade(self) -> None:
        result = self.run_harness(
            'OS_FAMILY=linux\nINSTALL_APP=1\ndetect_linux_app_support\nshow_plan',
            CODEX_TEST_LINUX_ID="arch", CODEX_TEST_LINUX_VERSION_ID="rolling",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("完整系统升级", result.stdout)
        self.assertIn("#install-on-arch-linux", result.stdout)

    def test_main_reports_optional_app_failure_and_preserves_configuration(self) -> None:
        config_dir = self.home / ".codex"
        config_dir.mkdir()
        config = config_dir / "config.toml"
        config.write_text('# user configuration must survive\n')
        # Stub only external installation and platform discovery. Execute the real
        # main, target/version validation, optional/required app handling and summary.
        harness = '''
detect_platform() { OS_FAMILY=linux; OS_NAME=Linux; ARCH=x64; }
detect_linux_app_support() { LINUX_APP_FORMAT=deb; }
download_bootstrap() { :; }
install_standalone() { :; }
install_linux_app() { return 9; }
main --non-interactive --install-app
'''
        result = self.run_harness(harness)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("完成（部分成功）", result.stdout)
        self.assertIn("ChatGPT Linux 桌面应用未完成", result.stdout)
        self.assertEqual(config.read_text(), '# user configuration must survive\n')
        self.assertEqual(list(self.base.glob("codex-installer.*")), [])

        required = self.run_harness(harness.replace("--install-app", "--require-app"))
        self.assertNotEqual(required.returncode, 0)
        self.assertNotIn("完成（部分成功）", required.stdout)
        self.assertEqual(config.read_text(), '# user configuration must survive\n')


if __name__ == "__main__":
    unittest.main()
