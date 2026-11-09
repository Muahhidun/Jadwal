"""Read-only gate for the *signed* Dauam archive/app/IPA, never an uploader.

Source entitlements and a successful codesign verification alone are insufficient:
an unsigned archive exported by cloud signing can lose App Groups entirely.
Run before export AND on an exported IPA before uploading it to TestFlight.
"""

import argparse
from datetime import datetime, timezone
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import zipfile

GROUP = "group.kz.dauam.shared"
TEAM = "ZV5872VU8H"
COMPONENTS = {
    ".": "kz.dauam",
    "PlugIns/JadwalWidgetExtension.appex": "kz.dauam.JadwalWidgetExtension",
    "Watch/Dauam.app": "kz.dauam.watchkitapp",
    "Watch/Dauam.app/PlugIns/DauamWatchWidgets.appex": "kz.dauam.watchkitapp.DauamWatchWidgets",
}


def validate_component(info, signed, profile, version, distribution=False):
    bundle_id = info["CFBundleIdentifier"]
    if str(info.get("CFBundleVersion")) != str(version):
        raise ValueError(f"{bundle_id}: inconsistent build number")
    expected_id = f"{TEAM}.{bundle_id}"
    for name, entitlements in [("signature", signed), ("profile", profile["Entitlements"])]:
        if GROUP not in entitlements.get("com.apple.security.application-groups", []):
            raise ValueError(f"{bundle_id}: {name} is missing App Group {GROUP}")
        if entitlements.get("application-identifier") != expected_id:
            raise ValueError(f"{bundle_id}: {name} has incorrect application identifier")
        if entitlements.get("com.apple.developer.team-identifier") != TEAM:
            raise ValueError(f"{bundle_id}: {name} has incorrect team")
        if distribution and entitlements.get("get-task-allow", False):
            raise ValueError(f"{bundle_id}: {name} allows debugging in distribution")
    expiry = profile["ExpirationDate"].replace(tzinfo=timezone.utc)
    if expiry <= datetime.now(timezone.utc):
        raise ValueError(f"{bundle_id}: expired provisioning profile")
    if distribution and (profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices")):
        raise ValueError(f"{bundle_id}: not an App Store distribution profile")


def run(*args):
    result = subprocess.run(args, capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f"{args[0]} failed: {result.stderr.decode(errors='replace')[:600]}")
    return result.stdout


def verify_app(root, distribution=False):
    version = plistlib.loads((root / "Info.plist").read_bytes())["CFBundleVersion"]
    # A structurally valid signature with missing capabilities must still fail.
    run("codesign", "--verify", "--deep", "--strict", str(root))
    for relative, expected_id in COMPONENTS.items():
        bundle = root / relative
        info = plistlib.loads((bundle / "Info.plist").read_bytes())
        if info["CFBundleIdentifier"] != expected_id:
            raise ValueError(f"Unexpected bundle at {relative}")
        signed = plistlib.loads(run("codesign", "-d", "--entitlements", ":-", str(bundle)))
        profile = plistlib.loads(run("security", "cms", "-D", "-i", str(bundle / "embedded.mobileprovision")))
        validate_component(info, signed, profile, version, distribution)
        print(f"OK: {expected_id} ({version}), signed App Group + profile")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path, help="Signed .xcarchive, .app, or exported .ipa")
    parser.add_argument("--distribution", action="store_true", help="Required for the exported TestFlight IPA")
    args = parser.parse_args()
    try:
        if args.path.suffix == ".ipa":
            with tempfile.TemporaryDirectory(prefix="dauam-release-gate-") as scratch:
                with zipfile.ZipFile(args.path) as archive:
                    for entry in archive.infolist():
                        path = Path(entry.filename)
                        if path.is_absolute() or ".." in path.parts or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                            raise ValueError("Unsafe path/symlink in IPA")
                    archive.extractall(scratch)
                apps = list((Path(scratch) / "Payload").glob("*.app"))
                if len(apps) != 1:
                    raise ValueError("Expected one application in IPA")
                verify_app(apps[0], args.distribution)
        else:
            root = args.path
            if root.suffix == ".xcarchive":
                root = root / "Products/Applications/Runner.app"
            verify_app(root, args.distribution)
    except (ValueError, OSError, KeyError, plistlib.InvalidFileException, zipfile.BadZipFile) as error:
        print(f"RELEASE BLOCKED: {error}", file=sys.stderr)
        return 1
    print("PASS: all four components can share widget data. No upload performed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
