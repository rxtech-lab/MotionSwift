#!/usr/bin/env python3
"""Relocate FFmpeg and its non-system Mach-O dependencies into a standalone app."""
import os
from pathlib import Path
import re
import plistlib
import shutil
import subprocess
import sys


def output(*args):
    return subprocess.check_output(args, text=True)


def bundle(app, executable):
    contents = app / "Contents"
    frameworks = contents / "Frameworks"
    helpers = contents / "Helpers"
    notices = contents / "Resources" / "ThirdParty"
    for directory in (frameworks, helpers, notices):
        directory.mkdir(parents=True, exist_ok=True)
    visited = {}
    destinations = {}

    def copy_binary(source, destination):
        source = source.resolve(strict=True)
        if source in visited:
            return visited[source]
        if destination in destinations and destinations[destination] != source:
            raise RuntimeError(f"Conflicting library names: {source}, {destinations[destination]}")
        destinations[destination] = source
        visited[source] = destination
        shutil.copy2(source, destination)
        destination.chmod(0o755)
        # Homebrew's formula, receipt, and installed license files record build provenance.
        if "Cellar" in source.parts:
            index = source.parts.index("Cellar")
            formula = Path(*source.parts[:index + 3])
            record = notices / (source.parts[index + 1] + "-" + source.parts[index + 2])
            if not record.exists():
                record.mkdir()
                for item in formula.iterdir():
                    if item.name == ".brew" or item.name == "INSTALL_RECEIPT.json" or re.match(
                        r"(?i)^(license|copying|copyright|notice)", item.name
                    ):
                        if item.is_dir():
                            shutil.copytree(item, record / item.name)
                        else:
                            shutil.copy2(item, record / item.name)
        # Rewritten load commands invalidate any existing ad-hoc signature.
        subprocess.run(["codesign", "--remove-signature", str(destination)], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        commands = output("otool", "-l", str(source))
        rpaths = re.findall(r"cmd LC_RPATH\n.*?\n\s*path (.*?) \(offset", commands)

        def expand(value):
            return Path(value.replace("@loader_path", str(source.parent)).replace(
                "@executable_path", str(executable.resolve().parent)))

        dependencies = [line.strip().split(" (compatibility")[0]
                        for line in output("otool", "-L", str(source)).splitlines()[1:]]
        for dependency in dependencies:
            if dependency.startswith(("/usr/lib/", "/System/Library/")):
                continue
            if dependency.startswith("@rpath/"):
                candidates = [expand(path) / dependency[len("@rpath/"):] for path in rpaths]
                resolved = next((path for path in candidates if path.exists()), None)
                if resolved is None:
                    raise RuntimeError(f"Cannot resolve {dependency} in {source}")
            else:
                resolved = expand(dependency)
            if resolved.resolve() == source:  # LC_ID_DYLIB is also listed by otool -L.
                continue
            target = copy_binary(resolved, frameworks / resolved.name)
            relative = os.path.relpath(target, destination.parent)
            subprocess.run(["install_name_tool", "-change", dependency,
                            "@loader_path/" + relative, str(destination)], check=True)
        if destination.suffix == ".dylib":
            subprocess.run(["install_name_tool", "-id", "@loader_path/" + destination.name,
                            str(destination)], check=True)
        # No build-machine search paths should survive packaging.
        for rpath in rpaths:
            subprocess.run(["install_name_tool", "-delete_rpath", rpath, str(destination)], check=True)
        return destination

    copy_binary(executable, helpers / "ffmpeg")
    (notices / "FFmpeg-license.txt").write_text(output(str(executable), "-L"))
    for binary in visited.values():
        links = output("otool", "-L", str(binary))
        if "/opt/homebrew/" in links or "/usr/local/" in links:
            raise RuntimeError(f"Unrelocated dependency in {binary}")
    # Homebrew bottles may target a newer OS than the app. Advertise the actual requirement.
    plist = contents / "Info.plist"
    info = plistlib.loads(plist.read_bytes())
    versions = [info['LSMinimumSystemVersion']]
    for binary in [contents / 'MacOS/motionswift-showcase', *visited.values()]:
        versions += re.findall(r'\bminos\s+([0-9.]+)', output('xcrun', 'vtool', '-show-build', str(binary)))
    info['LSMinimumSystemVersion'] = max(versions, key=lambda value: tuple(map(int, value.split('.'))))
    plist.write_bytes(plistlib.dumps(info))
    print(f"Bundled FFmpeg and {len(visited) - 1} libraries")


if __name__ == "__main__":
    bundle(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
