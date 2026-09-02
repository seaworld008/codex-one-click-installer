from __future__ import annotations

import base64
import json
import hashlib
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_VERSION = "2.1.0"
CHECKOUT_V7_0_1 = "3d3c42e5aac5ba805825da76410c181273ba90b1"
ATTEST_V4_2_2 = "1e69f48acb82d1966a394da916b4c1698aa569d6"
ACTIONLINT_V1_7_12 = "914e7df21a07ef503a81201c76d2b11c789d3fca"
EXPECTED_RELEASE_FILES = [
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "LICENSE",
    "README.md",
    "README.txt",
    "SECURITY.md",
    "SUPPORT.md",
    "VERSION",
    "Windows双击安装Codex.cmd",
    "Windows双击更新Codex.cmd",
    "docs/configuration.md",
    "docs/migration-v2.md",
    "docs/troubleshooting.md",
    "install-codex-linux.sh",
    "install-codex-macos.sh",
    "install-codex-unix.sh",
    "install-codex.ps1",
    "macOS双击安装Codex.command",
    "macOS双击更新Codex.command",
]
INSTALLER_SOURCES = [
    "install-codex-linux.sh",
    "install-codex-macos.sh",
    "install-codex.ps1",
    "install-codex-unix.sh",
]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8-sig")


def repository_files() -> list[Path]:
    result = subprocess.run(
        [
            "git",
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return [
        ROOT / raw.decode("utf-8")
        for raw in result.stdout.split(b"\0")
        if raw
    ]


class RepositoryContractTests(unittest.TestCase):
    def test_version_is_stable_semver(self) -> None:
        version = read("VERSION").strip()
        self.assertEqual(version, EXPECTED_VERSION)
        self.assertRegex(version, r"^\d+\.\d+\.\d+$")
        for relative in INSTALLER_SOURCES:
            self.assertNotIn(
                EXPECTED_VERSION,
                read(relative),
                f"{relative} must not embed the repository release version",
            )

    def test_release_manifest_is_explicit_sorted_and_complete(self) -> None:
        manifest = [
            line.strip()
            for line in read("scripts/release-files.txt").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        self.assertEqual(manifest, sorted(manifest))
        self.assertEqual(manifest, EXPECTED_RELEASE_FILES)
        self.assertEqual(len(manifest), len(set(manifest)))
        for relative in manifest:
            path = ROOT / relative
            self.assertTrue(path.is_file(), f"release source is missing: {relative}")
            self.assertNotIn(path.suffix.lower(), {".dmg", ".exe", ".msi", ".pkg"})
            self.assertFalse(
                {".git", ".github", "scripts", "tests"} & set(path.parts),
                f"forbidden release path: {relative}",
            )

    def test_no_binary_installers_or_private_overrides_are_tracked(self) -> None:
        forbidden_names = {
            "codex-auth.json",
            "downloads.local.json",
            "codex-auth.example.json",
            "downloads.local.example.json",
        }
        for path in repository_files():
            relative = path.relative_to(ROOT).as_posix()
            if not path.is_file():
                continue
            self.assertNotIn(path.name, forbidden_names, f"tracked private file: {relative}")
            self.assertNotIn(
                path.suffix.lower(),
                {".dll", ".dmg", ".exe", ".msi", ".pkg"},
                f"tracked binary installer: {relative}",
            )

    def test_no_likely_secrets(self) -> None:
        patterns = {
            "OpenAI API key": re.compile(rb"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}\b"),
            "GitHub token": re.compile(rb"\bgh[oprsu]_[A-Za-z0-9]{20,}\b"),
            "GitHub fine-grained token": re.compile(
                rb"\bgithub_pat_[A-Za-z0-9_]{20,}\b"
            ),
            "AWS access key": re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
            "private key": re.compile(rb"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----"),
        }
        for path in repository_files():
            relative = path.relative_to(ROOT)
            if not path.is_file() or relative.parts[0] == "tests":
                continue
            data = path.read_bytes()
            for label, pattern in patterns.items():
                self.assertIsNone(pattern.search(data), f"possible {label} in {relative}")

    def test_release_verifier_never_echoes_secret_matches(self) -> None:
        spec = importlib.util.spec_from_file_location(
            "codex_installer_verify_release",
            ROOT / "scripts/verify-release.py",
        )
        if spec is None or spec.loader is None:
            self.fail("could not load scripts/verify-release.py")
        verifier = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = verifier
        spec.loader.exec_module(verifier)
        verifier.SECRET_PATTERNS = (re.compile(rb"TEST_MATCH_SENTINEL"),)

        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / "release"
            root.mkdir()
            (root / "leak.txt").write_text(
                "TEST_MATCH_SENTINEL", encoding="utf-8"
            )
            (root / "VERSION").write_text(
                f"{EXPECTED_VERSION}\n", encoding="utf-8"
            )
            (root / "SBOM.spdx.json").write_text(
                json.dumps(
                    {
                        "spdxVersion": "SPDX-2.3",
                        "packages": [{"versionInfo": EXPECTED_VERSION}],
                    }
                ),
                encoding="utf-8",
            )
            manifest = base / "manifest.txt"
            manifest.write_text("VERSION\nleak.txt\n", encoding="utf-8")

            errors = verifier.validate_tree(root, manifest)
            self.assertIn("possible secret in leak.txt", errors)
            self.assertFalse(
                any("TEST_MATCH_SENTINEL" in error for error in errors)
            )

        source = read("scripts/verify-release.py")
        self.assertNotIn("for label, pattern", source)
        self.assertNotIn("match.group", source)

    def test_obsolete_installer_paths_are_absent(self) -> None:
        source = "\n".join(read(relative) for relative in INSTALLER_SOURCES)
        forbidden = [
            "LegacyGitVersion",
            "LegacyNodeVersion",
            "LegacyPython",
            "UseLatestDependencies",
            "CODEX_APP_INSTALLER_URL",
            "CODEX_SKILLS_URL",
            "npmmirror.com/mirrors",
        ]
        for token in forbidden:
            self.assertNotIn(token, source)

    def test_official_distribution_urls_and_store_id(self) -> None:
        all_relevant = "\n".join(
            read(relative)
            for relative in [
                *INSTALLER_SOURCES,
                "README.md",
                "README.txt",
                "scripts/check-upstreams.py",
            ]
        )
        required = [
            "https://chatgpt.com/codex/install.sh",
            "https://chatgpt.com/codex/install.ps1",
            "https://releases.openai.com/codex/install.sh",
            "https://releases.openai.com/codex/install.ps1",
            "https://releases.openai.com/codex/channels/latest",
            "https://get.microsoft.com/installer/download/9PLM9XGG6VKS",
            "https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb",
            "https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.x86_64.rpm",
            "9PLM9XGG6VKS",
        ]
        for value in required:
            self.assertIn(value, all_relevant)

        windows = read("install-codex.ps1")
        self.assertIn("https://releases.openai.com/codex/install.ps1", windows)
        self.assertIn("9PLM9XGG6VKS", windows)
        unix = read("install-codex-unix.sh")
        self.assertIn("https://releases.openai.com/codex/install.sh", unix)

    def test_readmes_share_platform_and_release_contract(self) -> None:
        markdown = read("README.md")
        text = read("README.txt")
        for content in (markdown, text):
            for entry in (
                "Windows双击安装Codex.cmd",
                "macOS双击安装Codex.command",
                "install-codex-linux.sh",
                "9PLM9XGG6VKS",
                "SHA256SUMS",
                "SPDX",
            ):
                self.assertIn(entry, content)
            self.assertRegex(content, r"Windows 8\s*/\s*8\.1.{0,20}不支持|不支持 Windows 8\s*/\s*8\.1")
            self.assertIn("19041", content)
        self.assertIn("v2.0.0", markdown)
        self.assertIn("v2", text)

    def test_gitattributes_and_gitignore_contract(self) -> None:
        attributes = read(".gitattributes")
        for rule in (
            "*.sh      text eol=lf",
            "*.command text eol=lf",
            "*.ps1 text eol=crlf",
            "*.cmd text eol=crlf",
            "*.exe  binary",
            "*.zip  binary",
        ):
            self.assertIn(rule, attributes)

        ignore = read(".gitignore")
        self.assertRegex(ignore, r"(?m)^dist/$")
        self.assertRegex(ignore, r"(?m)^\*\.exe$")
        self.assertNotIn("!Codex Installer.exe", ignore)

    def test_all_github_actions_are_pinned_to_full_commits(self) -> None:
        workflows = sorted((ROOT / ".github/workflows").glob("*.yml"))
        self.assertGreaterEqual(len(workflows), 3)
        uses_pattern = re.compile(r"(?m)^\s*-\s*uses:\s*([^@\s]+)@([^\s#]+)")
        for workflow in workflows:
            for action, revision in uses_pattern.findall(
                workflow.read_text(encoding="utf-8")
            ):
                self.assertRegex(
                    revision,
                    r"^[0-9a-f]{40}$",
                    f"{workflow.name}: {action}@{revision} is not immutable",
                )

    def test_checkout_is_v7_0_1_and_does_not_persist_credentials(self) -> None:
        workflows = sorted((ROOT / ".github/workflows").glob("*.yml"))
        checkout_count = 0
        for workflow in workflows:
            lines = workflow.read_text(encoding="utf-8").splitlines()
            for index, line in enumerate(lines):
                if "uses: actions/checkout@" not in line:
                    continue
                checkout_count += 1
                self.assertIn(
                    f"actions/checkout@{CHECKOUT_V7_0_1} # v7.0.1",
                    line,
                    f"{workflow.name} must pin checkout v7.0.1",
                )
                nearby = "\n".join(lines[index + 1 : index + 6])
                self.assertRegex(
                    nearby,
                    r"(?m)^\s+persist-credentials:\s*false\s*$",
                    f"{workflow.name} checkout must not retain a write credential",
                )
        self.assertGreater(checkout_count, 0)

    def test_compatibility_has_stable_aggregate_for_main_and_merge_queue(self) -> None:
        workflow = read(".github/workflows/compatibility.yml")
        self.assertIn("workflow_call:", workflow)
        self.assertIn("gate-result:", workflow)
        self.assertIn("value: ${{ jobs.gate.outputs.result }}", workflow)
        self.assertIn("merge_group:", workflow)
        self.assertIn("types: [checks_requested]", workflow)
        self.assertRegex(workflow, r"(?ms)push:\s+branches:\s+\[main\]")
        self.assertNotIn('"codex/**"', workflow)
        self.assertRegex(workflow, r"(?m)^  gate:\s*$")
        self.assertIn("name: Compatibility gate", workflow)
        self.assertIn(
            "needs: [static, linux-check-only, macos-check-only, windows]",
            workflow,
        )
        self.assertIn("if: ${{ always() }}", workflow)
        for dependency in (
            "needs.static.result",
            "needs.linux-check-only.result",
            "needs.macos-check-only.result",
            "needs.windows.result",
        ):
            self.assertIn(dependency, workflow)
        self.assertIn(
            "github.com/rhysd/actionlint/cmd/actionlint@"
            f"{ACTIONLINT_V1_7_12}",
            workflow,
        )
        powershell_steps = re.split(r"(?m)^      - name: ", workflow)
        native_exit_steps = [
            step for step in powershell_steps if "$LASTEXITCODE" in step
        ]
        self.assertEqual(len(native_exit_steps), 4)
        for step in native_exit_steps:
            self.assertRegex(
                step,
                r"(?m)^          exit 0\s*$",
                "PowerShell CI steps that accept expected native failures must "
                "reset the process exit code explicitly",
            )

    def test_release_automation_uses_shared_aggregate_and_exact_tag(self) -> None:
        workflow = read(".github/workflows/release.yml")
        self.assertIn('tags: ["v*"]', workflow)
        self.assertIn("scripts/package-release.sh", workflow)
        self.assertIn("--source-ref", workflow)
        self.assertIn("uses: ./.github/workflows/compatibility.yml", workflow)
        self.assertRegex(workflow, r"(?m)^  aggregate:\s*$")
        self.assertIn("needs: aggregate", workflow)
        self.assertIn(
            "if: ${{ needs.aggregate.outputs.gate-result == 'success' }}",
            workflow,
        )
        self.assertIn("gh release", workflow)
        self.assertNotRegex(workflow, r"(?i)(sed|perl).{0,30}VERSION")

        package_script = read("scripts/package-release.sh")
        self.assertIn("git -C \"$REPO_ROOT\" archive", package_script)
        self.assertIn("build-archives.py", package_script)
        self.assertIn("verify-release.py", package_script)
        self.assertIn("install -m", package_script)

    def test_release_requires_annotated_remote_tag_reachable_from_main(self) -> None:
        workflow = read(".github/workflows/release.yml")
        for contract in (
            'git cat-file -t "$tag_ref"',
            '"${tag_ref}^{tag}"',
            '"${tag_ref}^{commit}"',
            'git rev-parse "${GITHUB_SHA}^{commit}"',
            "refs/remotes/origin/main",
            'git merge-base --is-ancestor "$tag_commit" origin/main',
            "git ls-remote --tags origin",
            '"refs/tags/$tag^{}"',
            '"refs/tags/$RELEASE_TAG^{}"',
        ):
            self.assertIn(contract, workflow)
        self.assertGreaterEqual(
            workflow.count("verify_remote_tag"),
            9,
            "remote tag object and peeled commit must be rechecked around publishing",
        )
        self.assertEqual(
            workflow.count('remote_refs="$('),
            4,
            "each verifier must capture tag object and peeled commit in one remote query",
        )
        self.assertIn("RELEASE_TAG_OBJECT=", workflow)
        self.assertIn("RELEASE_TAG_COMMIT=", workflow)
        self.assertIn("RELEASE_EVENT_COMMIT=", workflow)

    def test_release_is_atomic_idempotent_and_never_clobbers_assets(self) -> None:
        workflow = read(".github/workflows/release.yml")
        self.assertNotIn("--clobber", workflow)
        for contract in (
            "Preflight existing release or create and verify exact draft",
            'gh release view "$RELEASE_TAG"',
            "--json isDraft,isPrerelease",
            'if .isPrerelease then "prerelease" elif .isDraft then "draft"',
            'gh release download "$RELEASE_TAG"',
            "scripts/verify-release-assets.py",
            "download_and_compare_release",
            "--compare-dir",
            "--draft",
            "--verify-tag",
            'gh release edit "$RELEASE_TAG" --draft=false --latest',
            "Existing public release is byte-for-byte identical; skipping attest and publish.",
            "Existing release is a prerelease; refusing to attest or mutate it.",
        ):
            self.assertIn(contract, workflow)

        preflight = workflow.index(
            "- name: Preflight existing release or create and verify exact draft"
        )
        first_attest = workflow.index("uses: actions/attest@")
        publish = workflow.index(
            "- name: Re-read and publish the verified draft"
        )
        self.assertLess(preflight, first_attest)
        self.assertLess(first_attest, publish)
        preflight_body = workflow[preflight:first_attest]
        self.assertIn('gh release create "$RELEASE_TAG"', preflight_body)
        self.assertIn('gh release download "$RELEASE_TAG"', preflight_body)
        self.assertIn("--compare-dir", preflight_body)
        self.assertNotIn("actions/attest@", preflight_body)
        publish_body = workflow[publish:]
        self.assertLess(
            publish_body.index('gh release download "$RELEASE_TAG"'),
            publish_body.index('gh release edit "$RELEASE_TAG" --draft=false --latest'),
        )
        self.assertIn("--compare-dir", publish_body)
        self.assertEqual(
            workflow.count(
                "if: ${{ steps.preflight.outputs.release_state == 'draft' }}"
            ),
            3,
        )
        self.assertGreaterEqual(workflow.count("scripts/verify-release-assets.py"), 5)

    def test_release_state_queries_are_unified_and_fail_closed(self) -> None:
        workflow = read(".github/workflows/release.yml")
        self.assertNotIn("gh api", workflow)
        self.assertNotIn("/releases/tags/", workflow)
        self.assertNotIn("HTTP 404", workflow)
        self.assertEqual(workflow.count("query_release_state()"), 3)
        self.assertEqual(workflow.count("$(query_release_state)"), 5)
        self.assertEqual(workflow.count('gh release view "$RELEASE_TAG"'), 3)

        helper_pattern = re.compile(
            r"(?ms)^          query_release_state\(\) \{\n"
            r"(.*?)"
            r"^          \}\n"
        )
        helper_bodies = helper_pattern.findall(workflow)
        self.assertEqual(len(helper_bodies), 3)
        self.assertTrue(
            all(body == helper_bodies[0] for body in helper_bodies[1:]),
            "every release-state read must use the same fail-closed helper",
        )
        helper = helper_bodies[0]
        for contract in (
            'gh release view "$RELEASE_TAG"',
            "--json isDraft,isPrerelease",
            "draft|prerelease|published)",
            'if [ "$error_text" = "release not found" ]; then',
            "printf 'missing\\n'",
            "Could not determine whether the release exists.",
            "return 1",
        ):
            self.assertIn(contract, helper)

        preflight_start = workflow.index(
            "- name: Preflight existing release or create and verify exact draft"
        )
        first_attest = workflow.index("uses: actions/attest@")
        preflight = workflow[preflight_start:first_attest]
        for contract in (
            'release_state="$(query_release_state)"',
            "draft|published)",
            "missing)",
            'created_state="$(query_release_state)"',
            'test "$created_state" = "draft"',
        ):
            self.assertIn(contract, preflight)

        publish_start = workflow.index("- name: Re-read and publish the verified draft")
        final_start = workflow.index(
            "- name: Verify public release assets and attestations"
        )
        publish = workflow[publish_start:final_start]
        self.assertIn('release_state="$(query_release_state)"', publish)
        self.assertIn('test "$release_state" = "draft"', publish)
        self.assertIn('published_state="$(query_release_state)"', publish)
        self.assertIn('test "$published_state" = "published"', publish)

    def test_public_release_rechecks_bytes_state_and_required_attestations(
        self,
    ) -> None:
        workflow = read(".github/workflows/release.yml")
        publish_index = workflow.index(
            'gh release edit "$RELEASE_TAG" --draft=false --latest'
        )
        final_index = workflow.index(
            "- name: Verify public release assets and attestations"
        )
        self.assertLess(publish_index, final_index)

        final = workflow[final_index:]
        header = final.split("run: |", maxsplit=1)[0]
        self.assertNotIn("if:", header)
        for contract in (
            'gh release download "$RELEASE_TAG"',
            "scripts/verify-release-assets.py",
            "--compare-dir",
            'release_state="$(query_release_state)"',
            'test "$release_state" = "published"',
            'gh attestation verify "$download_dir/$filename"',
            '--repo "$GITHUB_REPOSITORY"',
            '--signer-workflow "$GITHUB_REPOSITORY/.github/workflows/release.yml"',
            '--source-ref "refs/tags/$RELEASE_TAG"',
            '--source-digest "$RELEASE_TAG_COMMIT"',
            '--predicate-type "https://slsa.dev/provenance/v1"',
            '--predicate-type "https://spdx.dev/Document/v2.3"',
            '"${RELEASE_BASENAME}.spdx.json"',
        ):
            self.assertIn(contract, final)
        self.assertEqual(final.count('gh attestation verify "$download_dir/$filename"'), 2)
        self.assertEqual(final.count('--repo "$GITHUB_REPOSITORY"'), 2)
        self.assertEqual(
            final.count(
                '--signer-workflow "$GITHUB_REPOSITORY/.github/workflows/release.yml"'
            ),
            2,
        )
        self.assertEqual(final.count('--source-ref "refs/tags/$RELEASE_TAG"'), 2)
        self.assertEqual(final.count('--source-digest "$RELEASE_TAG_COMMIT"'), 2)
        self.assertIn("provenance_payloads=(", final)
        self.assertIn("sbom_payloads=(", final)

    def test_release_attests_payloads_and_external_spdx_sbom(self) -> None:
        workflow = read(".github/workflows/release.yml")
        self.assertEqual(
            workflow.count(f"uses: actions/attest@{ATTEST_V4_2_2} # v4.2.2"),
            2,
        )
        for permission in (
            "contents: write",
            "id-token: write",
            "attestations: write",
            "artifact-metadata: write",
        ):
            self.assertIn(permission, workflow)
        self.assertIn("subject-checksums: dist/SHA256SUMS", workflow)
        self.assertIn("subject-path: |", workflow)
        self.assertIn(
            "sbom-path: dist/${{ env.RELEASE_BASENAME }}.spdx.json", workflow
        )
        self.assertIn("dist/${{ env.RELEASE_BASENAME }}.zip", workflow)
        self.assertIn("dist/${{ env.RELEASE_BASENAME }}.tar.gz", workflow)

    def test_network_checks_are_separated_from_pull_request_gate(self) -> None:
        compatibility = read(".github/workflows/compatibility.yml")
        upstream = read(".github/workflows/upstream-smoke.yml")
        self.assertNotIn("VerifyDownloads", compatibility)
        self.assertNotIn("--verify-downloads", compatibility)
        self.assertIn("schedule:", upstream)
        self.assertIn("VerifyDownloads", upstream)
        self.assertIn("--verify-downloads", upstream)
        self.assertIn("scripts/check-upstreams.py", upstream)

    def test_upstream_windows_probes_use_canonical_docs_and_bounded_msix_size(
        self,
    ) -> None:
        source = read("scripts/check-upstreams.py")
        self.assertIn(
            'WINDOWS_DOCS = "https://learn.chatgpt.com/docs/windows/windows-app"',
            source,
        )
        self.assertIn('"Range": "bytes=0-3"', source)
        self.assertIn("Content-Range", source)
        self.assertIn(r'r"bytes\s+\d+-\d+/(\d+)"', source)
        self.assertIn("minimum=1024 * 1024", source)
        self.assertIn("maximum=1024 * 1024 * 1024", source)
        self.assertIn("unsafe total size", source)

    def test_upstream_linux_probes_use_official_docs_and_bounded_packages(
        self,
    ) -> None:
        source = read("scripts/check-upstreams.py")
        self.assertIn(
            'LINUX_DOCS = "https://learn.chatgpt.com/docs/linux/linux-app"',
            source,
        )
        for filename in (
            "chatgpt_amd64.deb",
            "chatgpt_arm64.deb",
            "chatgpt.x86_64.rpm",
            "chatgpt.aarch64.rpm",
        ):
            self.assertIn(filename, source)
        self.assertIn('headers={"Range": "bytes=0-7"', source)
        self.assertIn("minimum=10 * 1024 * 1024", source)
        self.assertIn("maximum=800 * 1024 * 1024", source)
        self.assertIn('expected = b"!<arch>\\n"', source)
        self.assertIn('expected = b"\\xed\\xab\\xee\\xdb"', source)

    def test_windows_downloads_are_bounded_and_msix_identity_is_verified(
        self,
    ) -> None:
        windows = read("install-codex.ps1")
        for contract in (
            "[Parameter(Mandatory=$true)][long]$MaximumBytes",
            "$response.ContentLength -gt $MaximumBytes",
            "$totalBytes + [long]$bytesRead -gt $MaximumBytes",
            "[System.Diagnostics.Stopwatch]::StartNew()",
            "$downloadTimer.ElapsedMilliseconds",
            "$asyncRead.AsyncWaitHandle.WaitOne([int]$remainingMilliseconds)",
            "$request.Abort()",
            "-MaximumBytes 2097152",
            "-MinimumBytes 1048576",
            "-MaximumBytes 1073741824",
            "-TimeoutMilliseconds 3600000",
            '$expectedName = "OpenAI.Codex"',
            '$expectedPublisher = "CN=50BDFD77-8903-4850-9FFE-6E8522F64D5B"',
            "AppxManifest.xml",
            "DtdProcessing]::Prohibit",
            "$document.XmlResolver = $null",
            "Get-AuthenticodeSignature",
            "SignatureStatus]::Valid",
            "Add-AppxPackage -Path",
            "function Resolve-CodexInstallDirectory",
            "CODEX_INSTALL_DIR 不得解析为驱动器根或 UNC 共享根",
            "$script:ValidatedCodexInstallDir",
            "(?![0-9A-Za-z.+-])",
            "https://github.com/openai/codex/releases/latest/download/install.ps1",
            "CODEX_INSTALLER_USE_RELEASES_OPENAI_COM",
            "OpenAI CDN 快速探测未通过",
            '[ValidateSet("auto", "official", "github")]',
            "function Download-AndValidateOfficialBootstrap",
            "function Download-OfficialBootstrap",
            '"true",',
        ):
            self.assertIn(contract, windows)
        helper = windows.split(
            "function Download-AndValidateOfficialBootstrap", maxsplit=1
        )[1].split("function Download-OfficialBootstrap", maxsplit=1)[0]
        self.assertLess(
            helper.index("Download-File"),
            helper.index("Test-OfficialBootstrap"),
        )
        self.assertIn(
            "Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue",
            helper,
        )
        self.assertNotIn('Arguments @("--registry"', windows)
        self.assertIn('"npm_config_registry", $NpmRegistry.Trim()', windows)
        standalone = windows.split(
            "function Invoke-StandaloneInstall", maxsplit=1
        )[1].split("function Get-NpmRelease", maxsplit=1)[0]
        self.assertIn('$script:BootstrapSource -eq "releases"', standalone)
        self.assertIn(
            '"CODEX_INSTALLER_USE_RELEASES_OPENAI_COM",\n                "true"',
            standalone,
        )

    def test_test_overrides_are_strictly_check_only(self) -> None:
        windows = read("install-codex.ps1")
        self.assertIn("function Assert-TestOverridesAreCheckOnly", windows)
        self.assertIn("$hasTestOverride -and -not $CheckOnly", windows)
        self.assertIn("[Nullable[int]]$TestProductType = $null", windows)
        self.assertIn("$null -ne $TestProductType", windows)
        self.assertIn("$null -eq $OsInfo.ProductType", windows)
        self.assertLess(
            windows.index("Assert-TestOverridesAreCheckOnly",  # definition
                          windows.index("$desktopRequested")),
            windows.index("Get-WindowsInfo", windows.index("$desktopRequested")),
        )

        unix = read("install-codex-unix.sh")
        self.assertIn("CODEX_TEST_* 仅允许与 --check-only 一起使用", unix)

        compatibility = read(".github/workflows/compatibility.yml")
        self.assertIn("Reject test-only overrides outside CheckOnly", compatibility)
        guard_step = compatibility.split(
            "- name: Reject test-only overrides outside CheckOnly", maxsplit=1
        )[1]
        self.assertNotIn('"-CheckOnly"', guard_step.split("\n\n", maxsplit=1)[0])
        self.assertIn("if ($exitCode -eq 0)", guard_step)
        self.assertIn("Validate custom standalone directory boundaries", compatibility)
        self.assertIn("Unsafe CODEX_INSTALL_DIR unexpectedly passed", compatibility)
        self.assertIn("Windows Server 2022 must fail", compatibility)
        self.assertIn("Unknown ProductType must fail", compatibility)
        self.assertIn("Validate desktop application minimum Windows build", compatibility)
        self.assertIn("required desktop fails below 19041", compatibility)

    def test_windows_double_click_defaults_do_not_install_dev_tools(self) -> None:
        for relative in (
            "Windows双击安装Codex.cmd",
            "Windows双击更新Codex.cmd",
        ):
            wrapper = read(relative)
            self.assertNotIn("-InstallDevTools", wrapper)
            self.assertNotIn("%*", wrapper)
            self.assertIn('-File "%SCRIPT_FILE%"', wrapper)
            self.assertIn("-NoPause", wrapper)
            self.assertIn('echo "%SCRIPT_FILE%"', wrapper)

    def test_unix_download_limit_path_binding_and_wrapper_binding(self) -> None:
        unix = read("install-codex-unix.sh")
        for contract in (
            'BOOTSTRAP_MAX_BYTES=1048576',
            'head -c "$((BOOTSTRAP_MAX_BYTES + 1))"',
            'part="$WORK_DIR/install.sh.part.$attempt"',
            'rm -f "$part"',
            'validate_https_url "$BOOTSTRAP_URL" "CODEX_BOOTSTRAP_URL" 1',
            'target="$WORK_DIR/install.sh"',
            'mv "$part" "$target"',
            '/bin/sh "$WORK_DIR/install.sh"',
            "https://github.com/openai/codex/releases/latest/download/install.sh",
            "CODEX_INSTALLER_USE_RELEASES_OPENAI_COM=false",
            "CODEX_INSTALLER_USE_RELEASES_OPENAI_COM=true",
            "--network 仅支持 auto、official 或 github",
        ):
            self.assertIn(contract, unix)
        standalone = unix.split("install_standalone() {", maxsplit=1)[1].split(
            "install_brew() {", maxsplit=1
        )[0]
        self.assertIn(
            'elif [ "$BOOTSTRAP_SOURCE" = "releases" ]; then',
            standalone,
        )
        self.assertIn("[^0-9A-Za-z.+-]", unix)
        for wrapper_path in (
            "install-codex-linux.sh",
            "install-codex-macos.sh",
            "macOS双击安装Codex.command",
            "macOS双击更新Codex.command",
        ):
            wrapper = read(wrapper_path)
            self.assertIn('CORE_SCRIPT="$SCRIPT_DIR/install-codex-unix.sh"', wrapper)
            self.assertRegex(wrapper, r'(?:exec )?/bin/bash "\$CORE_SCRIPT"')

    def test_unix_download_retries_are_fresh_and_oversize_is_bounded(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            fake_bin = base / "bin"
            temp_root = base / "tmp"
            fake_bin.mkdir()
            temp_root.mkdir()
            fake_curl = fake_bin / "curl"
            valid_bootstrap = base / "valid-install.sh"
            valid_bootstrap.write_text(
                "#!/bin/sh\n"
                "# Codex CLI official-compatible test fixture\n"
                "CODEX_RELEASE=latest\n"
                "# supports --release\n"
                + ("# bounded fixture padding\n" * 64),
                encoding="utf-8",
            )
            state = base / "attempts"
            fake_curl.write_text(
                "#!/bin/sh\n"
                'count=0\n'
                '[ ! -f "$FAKE_CURL_STATE" ] || count="$(/bin/cat "$FAKE_CURL_STATE")"\n'
                'count=$((count + 1))\n'
                'printf "%s\\n" "$count" >"$FAKE_CURL_STATE"\n'
                'if [ "$count" -eq 1 ]; then\n'
                '  printf "truncated first response\\n"\n'
                "  exit 22\n"
                "fi\n"
                'exec /bin/cat "$FAKE_BOOTSTRAP"\n',
                encoding="utf-8",
            )
            fake_curl.chmod(0o755)
            environment = {
                **os.environ,
                "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
                "TMPDIR": str(temp_root),
                "FAKE_CURL_STATE": str(state),
                "FAKE_BOOTSTRAP": str(valid_bootstrap),
                "CODEX_TEST_UNAME_S": "Linux",
                "CODEX_TEST_ARCH": "x86_64",
                "CODEX_TEST_OS_VERSION": "Test Linux",
            }
            retry_result = subprocess.run(
                [
                    "bash",
                    str(ROOT / "install-codex-unix.sh"),
                    "--check-only",
                    "--verify-downloads",
                    "--non-interactive",
                ],
                cwd=ROOT,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(retry_result.returncode, 0, retry_result.stderr)
            self.assertEqual(state.read_text(encoding="utf-8").strip(), "2")
            self.assertIn("bootstrap 下载与内容校验通过", retry_result.stdout)
            self.assertEqual(list(temp_root.glob("codex-installer.*")), [])

            fake_curl.write_text(
                "#!/bin/sh\n"
                "dd if=/dev/zero bs=1048576 count=2 2>/dev/null\n",
                encoding="utf-8",
            )
            fake_curl.chmod(0o755)
            oversize_result = subprocess.run(
                [
                    "bash",
                    str(ROOT / "install-codex-unix.sh"),
                    "--check-only",
                    "--verify-downloads",
                    "--non-interactive",
                ],
                cwd=ROOT,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(oversize_result.returncode, 0)
            self.assertIn("超过安全上限", oversize_result.stderr)
            self.assertEqual(list(temp_root.glob("codex-installer.*")), [])

    def test_unix_auto_network_rejects_invalid_cdn_payload_and_falls_back(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            fake_bin = base / "bin"
            temp_root = base / "tmp"
            fake_bin.mkdir()
            temp_root.mkdir()
            fake_curl = fake_bin / "curl"
            valid_bootstrap = base / "valid-install.sh"
            valid_bootstrap.write_text(
                "#!/bin/sh\n"
                "# Codex CLI official-compatible test fixture\n"
                "CODEX_RELEASE=latest\n"
                "# supports --release\n"
                + ("# bounded fixture padding\n" * 64),
                encoding="utf-8",
            )
            calls = base / "calls"
            fake_curl.write_text(
                "#!/bin/sh\n"
                'for argument in "$@"; do url="$argument"; done\n'
                'printf "%s\\n" "$url" >>"$FAKE_CURL_CALLS"\n'
                'case "$url" in\n'
                "  https://releases.openai.com/*) "
                "printf '<!doctype html>\\n'; "
                "dd if=/dev/zero bs=4096 count=2 2>/dev/null ;;\n"
                "  https://github.com/openai/codex/releases/*) "
                'exec /bin/cat "$FAKE_BOOTSTRAP" ;;\n'
                "  *) exit 22 ;;\n"
                "esac\n",
                encoding="utf-8",
            )
            fake_curl.chmod(0o755)
            environment = {
                **os.environ,
                "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
                "TMPDIR": str(temp_root),
                "FAKE_CURL_CALLS": str(calls),
                "FAKE_BOOTSTRAP": str(valid_bootstrap),
                "CODEX_TEST_UNAME_S": "Linux",
                "CODEX_TEST_ARCH": "x86_64",
                "CODEX_TEST_OS_VERSION": "Test Linux",
            }
            result = subprocess.run(
                [
                    "bash",
                    str(ROOT / "install-codex-unix.sh"),
                    "--check-only",
                    "--verify-downloads",
                    "--non-interactive",
                ],
                cwd=ROOT,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("未通过校验", result.stderr)
            self.assertIn("自动切换 OpenAI GitHub Release", result.stdout)
            self.assertIn("bootstrap 来源：OpenAI GitHub Release", result.stdout)
            call_log = calls.read_text(encoding="utf-8")
            self.assertIn("https://releases.openai.com/codex/install.sh", call_log)
            self.assertIn(
                "https://github.com/openai/codex/releases/latest/download/install.sh",
                call_log,
            )

            fake_curl.write_text(
                "#!/bin/sh\n"
                'for argument in "$@"; do url="$argument"; done\n'
                'case "$url" in\n'
                "  https://releases.openai.com/*) "
                "dd if=/dev/zero bs=1048576 count=2 2>/dev/null ;;\n"
                "  https://github.com/openai/codex/releases/*) "
                'exec /bin/cat "$FAKE_BOOTSTRAP" ;;\n'
                "  *) exit 22 ;;\n"
                "esac\n",
                encoding="utf-8",
            )
            fake_curl.chmod(0o755)
            oversize_fallback = subprocess.run(
                [
                    "bash",
                    str(ROOT / "install-codex-unix.sh"),
                    "--check-only",
                    "--verify-downloads",
                    "--non-interactive",
                ],
                cwd=ROOT,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                oversize_fallback.returncode,
                0,
                oversize_fallback.stderr,
            )
            self.assertIn("超过安全上限", oversize_fallback.stderr)
            self.assertIn(
                "bootstrap 来源：OpenAI GitHub Release",
                oversize_fallback.stdout,
            )

    def test_linux_app_retry_discards_partial_response(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            fake_bin = base / "bin"
            work_dir = base / "work"
            target = work_dir / "chatgpt.deb"
            state = base / "curl-state"
            fake_bin.mkdir()
            work_dir.mkdir()

            fake_curl = fake_bin / "curl"
            fake_curl.write_text(
                "#!/bin/sh\n"
                "count=0\n"
                '[ ! -f "$FAKE_CURL_STATE" ] || '
                'count="$(/bin/cat "$FAKE_CURL_STATE")"\n'
                "count=$((count + 1))\n"
                'printf "%s" "$count" >"$FAKE_CURL_STATE"\n'
                'if [ "$count" -eq 1 ]; then\n'
                "  printf 'partial-first-response'\n"
                "  exit 56\n"
                "fi\n"
                "printf 'clean-second-response'\n",
                encoding="utf-8",
            )
            fake_curl.chmod(0o755)

            unix = read("install-codex-unix.sh")
            definitions = unix.rsplit('\nmain "$@"', maxsplit=1)[0]
            harness = base / "download-linux-app.sh"
            harness.write_text(
                definitions
                + "\nLINUX_APP_MIN_BYTES=5\n"
                + "LINUX_APP_MAX_BYTES=64\n"
                + 'WORK_DIR="$FAKE_WORK_DIR"\n'
                + "trap - EXIT\n"
                + 'download_linux_app "https://example.invalid/chatgpt.deb" '
                + '"$FAKE_TARGET"\n',
                encoding="utf-8",
            )

            result = subprocess.run(
                ["bash", str(harness)],
                cwd=ROOT,
                env={
                    **os.environ,
                    "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
                    "FAKE_CURL_STATE": str(state),
                    "FAKE_WORK_DIR": str(work_dir),
                    "FAKE_TARGET": str(target),
                },
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(state.read_text(encoding="utf-8"), "2")
            self.assertEqual(
                target.read_text(encoding="utf-8"),
                "clean-second-response",
            )
            self.assertEqual(list(work_dir.glob("*.part.*")), [])

    def test_linux_wrapper_defaults_to_official_desktop_app(self) -> None:
        wrapper = read("install-codex-linux.sh")
        self.assertIn(
            'exec /bin/bash "$CORE_SCRIPT" --install-app "$@"',
            wrapper,
        )
        unix = read("install-codex-unix.sh")
        for contract in (
            "ubuntu:24.04|ubuntu:26.04|debian:13",
            "fedora:43|fedora:44",
            "dpkg-deb -f",
            "rpm -qp --queryformat",
            'name" = "chatgpt',
            "LINUX_APP_MAX_BYTES=838860800",
            'part="$target.part.$attempt"',
            "--skip-app",
            "(trap - EXIT; install_linux_app)",
            "if ! run_privileged apt install -y",
            "if ! run_privileged dnf install -y",
            "apt 安装 ChatGPT Linux 桌面包失败",
            "dnf 安装 ChatGPT Linux 桌面包失败",
        ):
            self.assertIn(contract, unix)
        self.assertNotIn("--retry-all-errors", unix)

        environment = {
            **os.environ,
            "CODEX_TEST_UNAME_S": "Linux",
            "CODEX_TEST_ARCH": "aarch64",
            "CODEX_TEST_OS_VERSION": "Ubuntu 24.04 LTS",
            "CODEX_TEST_LINUX_ID": "ubuntu",
            "CODEX_TEST_LINUX_VERSION_ID": "24.04",
        }
        result = subprocess.run(
            [
                "bash",
                str(ROOT / "install-codex-linux.sh"),
                "--check-only",
                "--non-interactive",
            ],
            cwd=ROOT,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("官方 Linux deb 包（ubuntu 24.04）", result.stdout)

    def test_installers_print_post_install_configuration_reference(self) -> None:
        unix = read("install-codex-unix.sh")
        windows = read("install-codex.ps1")
        docs = read("docs/configuration.md")
        self.assertIn("~/.codex/config.toml", unix)
        self.assertIn(r"$HOME\.codex\config.toml", windows)
        self.assertIn("~/.codex/config.toml", docs)
        for content in (unix, windows, docs):
            self.assertIn('model = "gpt-5.6"', content)
            self.assertIn('approval_policy = "on-request"', content)
            self.assertIn('sandbox_mode = "workspace-write"', content)
            self.assertIn("codex --strict-config --version", content)
        self.assertIn("show_post_install_guide", unix)
        self.assertIn("Show-PostInstallGuide", windows)
        self.assertIn("docs/configuration.md", unix)
        self.assertIn("docs/configuration.md", windows)

    def test_enterprise_ca_documentation_matches_bootstrap_trust_boundaries(
        self,
    ) -> None:
        documents = {
            "README.md": read("README.md"),
            "README.txt": read("README.txt"),
            "docs/troubleshooting.md": read("docs/troubleshooting.md"),
        }
        for relative, content in documents.items():
            self.assertIn("CURL_CA_BUNDLE", content, relative)
            self.assertIn("CODEX_CA_CERTIFICATE", content, relative)
            self.assertIn("受信任根", content, relative)
            self.assertRegex(
                content,
                r"CODEX_CA_CERTIFICATE.{0,60}(?:运行期|安装后)",
                relative,
            )
        troubleshooting = documents["docs/troubleshooting.md"]
        self.assertIn("curl/Windows 系统信任", troubleshooting)
        self.assertIn("不要使用 `curl -k`", troubleshooting)

    def test_windows_source_encoding_contract(self) -> None:
        powershell = (ROOT / "install-codex.ps1").read_bytes()
        self.assertTrue(
            powershell.startswith(b"\xef\xbb\xbf"),
            "Windows PowerShell 5.1 requires the UTF-8 BOM for Chinese source",
        )
        for relative in ("Windows双击安装Codex.cmd", "Windows双击更新Codex.cmd"):
            data = (ROOT / relative).read_bytes()
            self.assertFalse(data.startswith(b"\xef\xbb\xbf"))
            data.decode("ascii")


class SbomTests(unittest.TestCase):
    def test_stdlib_generator_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            source = base / "source"
            source.mkdir()
            (source / "VERSION").write_text(
                f"{EXPECTED_VERSION}\n", encoding="utf-8"
            )
            output_one = base / "one.json"
            output_two = base / "two.json"
            command = [
                sys.executable,
                str(ROOT / "scripts/generate-sbom.py"),
                "--root",
                str(source),
                "--version",
                EXPECTED_VERSION,
                "--output",
            ]
            environment = {**os.environ, "SOURCE_DATE_EPOCH": "0"}
            subprocess.run(command + [str(output_one)], check=True, env=environment)
            subprocess.run(command + [str(output_two)], check=True, env=environment)
            self.assertEqual(output_one.read_bytes(), output_two.read_bytes())
            document = json.loads(output_one.read_text(encoding="utf-8"))
            self.assertEqual(document["spdxVersion"], "SPDX-2.3")
            self.assertEqual(document["packages"][0]["versionInfo"], EXPECTED_VERSION)
            self.assertEqual(
                document["creationInfo"]["created"], "1970-01-01T00:00:00Z"
            )


class UpstreamProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        spec = importlib.util.spec_from_file_location(
            "codex_installer_check_upstreams",
            ROOT / "scripts/check-upstreams.py",
        )
        if spec is None or spec.loader is None:
            raise RuntimeError("could not load scripts/check-upstreams.py")
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        cls.probes = module

    def response(self, status: int, headers: dict[str, str]):
        return self.probes.Response(
            url="https://example.invalid/package.msix",
            status=status,
            headers=headers,
            body=b"PK",
        )

    def test_range_total_is_parsed_and_bounded(self) -> None:
        size = self.probes.parse_bounded_total_bytes(
            self.response(206, {"Content-Range": "bytes 0-3/761843469"}),
            "MSIX",
            minimum=1024 * 1024,
            maximum=1024 * 1024 * 1024,
        )
        self.assertEqual(size, 761843469)

    def test_full_response_uses_content_length(self) -> None:
        size = self.probes.parse_bounded_total_bytes(
            self.response(200, {"Content-Length": "1048576"}),
            "MSIX",
            minimum=1024 * 1024,
            maximum=1024 * 1024 * 1024,
        )
        self.assertEqual(size, 1048576)

    def test_missing_or_unsafe_total_is_rejected(self) -> None:
        cases = (
            self.response(206, {"Content-Range": "bytes 0-3/*"}),
            self.response(200, {}),
            self.response(206, {"Content-Range": "bytes 0-3/1048575"}),
            self.response(206, {"Content-Range": "bytes 0-3/1073741825"}),
        )
        for response in cases:
            with self.subTest(status=response.status, headers=response.headers):
                with self.assertRaises(self.probes.ProbeError):
                    self.probes.parse_bounded_total_bytes(
                        response,
                        "MSIX",
                        minimum=1024 * 1024,
                        maximum=1024 * 1024 * 1024,
                    )

    def test_npm_integrity_requires_exact_sha512_digest(self) -> None:
        valid = "sha512-" + base64.b64encode(b"x" * 64).decode("ascii")
        self.probes.validate_sha512_integrity(valid)
        for invalid in (
            None,
            "sha512-",
            "sha512-not-base64!",
            "sha512-" + base64.b64encode(b"x" * 63).decode("ascii"),
            "sha256-" + base64.b64encode(b"x" * 64).decode("ascii"),
        ):
            with self.subTest(value=invalid):
                with self.assertRaises(self.probes.ProbeError):
                    self.probes.validate_sha512_integrity(invalid)

    def test_linux_package_prefix_requires_deb_or_rpm_magic(self) -> None:
        self.probes.validate_linux_package_prefix(
            "chatgpt_amd64.deb",
            b"!<arch>\nrest",
        )
        self.probes.validate_linux_package_prefix(
            "chatgpt.x86_64.rpm",
            b"\xed\xab\xee\xdbrest",
        )
        for filename, body in (
            ("chatgpt_amd64.deb", b"<html>"),
            ("chatgpt.x86_64.rpm", b"PK\x03\x04"),
            ("chatgpt.bin", b"!<arch>\n"),
        ):
            with self.subTest(filename=filename):
                with self.assertRaises(self.probes.ProbeError):
                    self.probes.validate_linux_package_prefix(filename, body)


class ReleaseAssetVerificationTests(unittest.TestCase):
    BASENAME = "codex-one-click-installer-v2.0.0"

    @classmethod
    def setUpClass(cls) -> None:
        spec = importlib.util.spec_from_file_location(
            "codex_installer_verify_release_assets",
            ROOT / "scripts/verify-release-assets.py",
        )
        if spec is None or spec.loader is None:
            raise RuntimeError("could not load scripts/verify-release-assets.py")
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        cls.assets = module

    def write_fixture(self, root: Path, marker: bytes = b"local") -> None:
        root.mkdir(parents=True)
        payloads, _ = self.assets.expected_names(self.BASENAME)
        for index, filename in enumerate(payloads):
            (root / filename).write_bytes(
                marker + b":" + str(index).encode("ascii") + b"\n"
            )
        checksum_lines = [
            f"{self.assets.sha256(root / filename)}  {filename}\n"
            for filename in payloads
        ]
        (root / "SHA256SUMS").write_text(
            "".join(checksum_lines), encoding="ascii", newline="\n"
        )

    def test_exact_local_and_downloaded_assets_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            local = base / "local"
            downloaded = base / "downloaded"
            self.write_fixture(local)
            shutil.copytree(local, downloaded)
            records = self.assets.verify_directory(local, self.BASENAME)
            self.assertEqual(len(records), 3)
            self.assets.compare_directories(local, downloaded, self.BASENAME)

    def test_file_list_checksum_and_symlink_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            cases = []

            extra = base / "extra"
            self.write_fixture(extra)
            (extra / "unexpected.txt").write_text("unexpected\n", encoding="utf-8")
            cases.append(
                (
                    "extra file",
                    lambda: self.assets.verify_directory(extra, self.BASENAME),
                )
            )

            missing = base / "missing"
            self.write_fixture(missing)
            (missing / f"{self.BASENAME}.zip").unlink()
            cases.append(
                (
                    "missing file",
                    lambda: self.assets.verify_directory(missing, self.BASENAME),
                )
            )

            malformed = base / "malformed"
            self.write_fixture(malformed)
            (malformed / "SHA256SUMS").write_text(
                f"{'0' * 64}  ../escape.zip\n", encoding="ascii"
            )
            cases.append(
                (
                    "unsafe checksum name",
                    lambda: self.assets.verify_directory(malformed, self.BASENAME),
                )
            )

            mismatch = base / "mismatch"
            self.write_fixture(mismatch)
            with (mismatch / f"{self.BASENAME}.tar.gz").open("ab") as handle:
                handle.write(b"changed")
            cases.append(
                (
                    "digest mismatch",
                    lambda: self.assets.verify_directory(mismatch, self.BASENAME),
                )
            )

            symlinked = base / "symlinked"
            self.write_fixture(symlinked)
            payload = symlinked / f"{self.BASENAME}.spdx.json"
            payload.unlink()
            payload.symlink_to(symlinked / f"{self.BASENAME}.zip")
            cases.append(
                (
                    "symlink",
                    lambda: self.assets.verify_directory(symlinked, self.BASENAME),
                )
            )

            for label, check in cases:
                with self.subTest(label=label):
                    with self.assertRaises(self.assets.VerificationError):
                        check()

    def test_byte_different_but_individually_valid_download_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            local = base / "local"
            downloaded = base / "downloaded"
            self.write_fixture(local, marker=b"local")
            self.write_fixture(downloaded, marker=b"remote")
            self.assets.verify_directory(local, self.BASENAME)
            self.assets.verify_directory(downloaded, self.BASENAME)
            with self.assertRaises(self.assets.VerificationError):
                self.assets.compare_directories(local, downloaded, self.BASENAME)


class ReleasePackageTests(unittest.TestCase):
    def test_source_ref_must_be_non_empty_and_is_resolved_once(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(
                [
                    "bash",
                    str(ROOT / "scripts/package-release.sh"),
                    "--source-ref",
                    "",
                    "--output-dir",
                    temporary,
                ],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("--source-ref requires a non-empty value", result.stderr)

        script = read("scripts/package-release.sh")
        self.assertIn('SOURCE_COMMIT="$(', script)
        self.assertIn('archive --format=tar "$SOURCE_COMMIT"', script)
        self.assertIn('show "${SOURCE_COMMIT}:VERSION"', script)
        self.assertIn('SOURCE_DATE_EPOCH="$(git -C "$REPO_ROOT" show', script)
        self.assertIn('--format=%ct "$SOURCE_COMMIT")"', script)

    def copy_packaging_fixture(self, destination: Path) -> None:
        for relative in [
            *EXPECTED_RELEASE_FILES,
            "scripts/build-archives.py",
            "scripts/generate-sbom.py",
            "scripts/package-release.sh",
            "scripts/release-files.txt",
            "scripts/verify-release.py",
        ]:
            source = ROOT / relative
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)

    def test_packager_rejects_symlink_sources_and_unsafe_manifest_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)

            symlink_fixture = base / "symlink-fixture"
            self.copy_packaging_fixture(symlink_fixture)
            outside = base / "outside.md"
            outside.write_text("host-only content\n", encoding="utf-8")
            (symlink_fixture / "README.md").unlink()
            (symlink_fixture / "README.md").symlink_to(outside)
            symlink_result = subprocess.run(
                [
                    "bash",
                    str(symlink_fixture / "scripts/package-release.sh"),
                    "--output-dir",
                    str(base / "symlink-output"),
                ],
                cwd=symlink_fixture,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(symlink_result.returncode, 0)
            self.assertIn("symbolic links", symlink_result.stderr)

            manifest_fixture = base / "manifest-fixture"
            self.copy_packaging_fixture(manifest_fixture)
            manifest = manifest_fixture / "scripts/release-files.txt"
            manifest.write_text(
                manifest.read_text(encoding="utf-8") + "../outside.md\n",
                encoding="utf-8",
            )
            manifest_result = subprocess.run(
                [
                    "bash",
                    str(manifest_fixture / "scripts/package-release.sh"),
                    "--output-dir",
                    str(base / "manifest-output"),
                ],
                cwd=manifest_fixture,
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(manifest_result.returncode, 0)
            self.assertIn("unsafe release manifest path", manifest_result.stderr)

    def test_two_builds_are_byte_for_byte_reproducible(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            outputs = [base / "one", base / "two"]
            environment = {**os.environ, "SOURCE_DATE_EPOCH": "1787644800"}
            for output in outputs:
                subprocess.run(
                    [
                        "bash",
                        str(ROOT / "scripts/package-release.sh"),
                        "--output-dir",
                        str(output),
                    ],
                    cwd=ROOT,
                    check=True,
                    env=environment,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                )

            asset_names = {
                path.name
                for path in outputs[0].iterdir()
                if path.name != "SHA256SUMS"
            }
            self.assertEqual(
                asset_names,
                {
                    f"codex-one-click-installer-v{EXPECTED_VERSION}.zip",
                    f"codex-one-click-installer-v{EXPECTED_VERSION}.tar.gz",
                    f"codex-one-click-installer-v{EXPECTED_VERSION}.spdx.json",
                },
            )
            for name in sorted(asset_names):
                first = hashlib.sha256((outputs[0] / name).read_bytes()).digest()
                second = hashlib.sha256((outputs[1] / name).read_bytes()).digest()
                self.assertEqual(first, second, f"non-reproducible release asset: {name}")
            self.assertEqual(
                (outputs[0] / "SHA256SUMS").read_bytes(),
                (outputs[1] / "SHA256SUMS").read_bytes(),
            )


if __name__ == "__main__":
    unittest.main()
