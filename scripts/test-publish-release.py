#!/usr/bin/env python3
"""Exercise release publication and retries with a local fake GitHub CLI."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

SCRIPT = Path(__file__).with_name("publish-release.sh")
CHANNEL = "quill-rc-channel"

def appcast(build):
    return f'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>{build}</sparkle:version></item></channel></rss>'

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    state_path = root / "state.json"
    state_path.write_text(json.dumps({"releases": {}, "uploads": []}))
    fake = root / "gh"
    fake.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
path = pathlib.Path(os.environ["TEST_STATE"])
state = json.loads(path.read_text())
args = sys.argv[1:]
def option(name):
    return args[args.index(name) + 1]
def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)
if args[0] == "api":
    assert args[1] == "graphql", "REST tag lookups cannot find draft releases"
    if os.environ.get("FAIL_API"):
        fail("gh: Forbidden (HTTP 403)")
    tag = next((arg[4:] for arg in args if arg.startswith("tag=")), None)
    if tag is None:
        print(state.get("latest", ""))
        sys.exit(0)
    if tag not in state["releases"]:
        print("missing")
        sys.exit(0)
    release = state["releases"][tag]
    print(str(release["draft"]).lower(), str(release["prerelease"]).lower())
    sys.exit(0)
command, tag = args[1:3]
if command == "create":
    assert tag not in state["releases"]
    assert "--draft" in args
    state["releases"][tag] = {
        "draft": True,
        "prerelease": "--prerelease" in args or "--prerelease=true" in args,
        "assets": {},
    }
else:
    release = state["releases"][tag]
    if command == "upload":
        if os.environ.get("FAIL_AFTER_DELETE") == tag:
            release["assets"].pop("appcast.xml", None)
            path.write_text(json.dumps(state))
            fail("simulated failure after clobber deleted appcast")
        if os.environ.get("FAIL_UPLOAD") == tag:
            fail("simulated upload failure")
        assert tag == "quill-rc-channel" or release["draft"], "changed published binaries"
        for name in args[3:]:
            if not name.startswith("--"):
                asset = pathlib.Path(name)
                release["assets"][asset.name] = asset.read_text()
        state["uploads"].append(tag)
    elif command == "edit":
        assert "appcast.xml" in release["assets"], "published before assets"
        if tag != "quill-rc-channel":
            assert "Quill-macOS.dmg" in release["assets"]
            assert ("--latest=false" if release["prerelease"] else "--latest=true") in args
            if not release["prerelease"]:
                state["latest"] = tag
        release["draft"] = False
    elif command == "download":
        name = option("--pattern")
        if name not in release["assets"]:
            fail("missing asset")
        (pathlib.Path(option("--dir")) / name).write_text(release["assets"][name])
    else:
        fail("unexpected command")
path.write_text(json.dumps(state))
''')
    fake.chmod(0o755)
    dmg = root / "Quill-v1.0.0-macOS.dmg"
    dmg.write_text("signed binary")
    feed = root / "appcast.xml"
    feed.write_text(appcast(10))
    env = {
        **os.environ,
        "PATH": f"{root}:{os.environ['PATH']}",
        "GITHUB_REPOSITORY": "test/quill",
        "RUNNER_TEMP": str(root),
        "TEST_STATE": str(state_path),
        "DMG_PATH": str(dmg),
        "APPCAST_PATH": str(feed),
    }

    def run(action, tag="v1.0.0", prerelease="false", failure=None):
        result = subprocess.run([str(SCRIPT), action, tag, prerelease],
                                env={**env, **(failure or {})}, capture_output=True, text=True)
        assert (result.returncode != 0) == bool(failure), result.stderr
        return result.stdout

    assert run("prepare") == "needs_build=true\n"
    run("publish", failure={"FAIL_UPLOAD": "v1.0.0"})
    assert json.loads(state_path.read_text())["releases"]["v1.0.0"]["draft"]
    run("publish", failure={"FAIL_UPLOAD": CHANNEL})
    assert run("prepare") == "needs_build=false\n"
    run("publish")  # Recover after public binaries exist but channel upload failed.
    state = json.loads(state_path.read_text())
    assert state["uploads"] == ["v1.0.0", CHANNEL]
    assert all(not release["draft"] for release in state["releases"].values())
    run("publish")  # Completed release is a no-op.
    assert json.loads(state_path.read_text()) == state

    feed.write_text(appcast(20))
    run("publish", "v1.1.0-rc.1", "true")
    state = json.loads(state_path.read_text())
    assert state["releases"]["v1.1.0-rc.1"]["prerelease"]
    assert "20" in state["releases"][CHANNEL]["assets"]["appcast.xml"]
    run("publish")  # Replaying an older release cannot roll the channel back.
    assert json.loads(state_path.read_text()) == state
    run("prepare", failure={"FAIL_API": "1"})  # API errors are not missing releases.
    # An older unfinished tag cannot get a new build number and downgrade either feed.
    for tag, prerelease in [("v0.9.0", "false"), ("v1.0.0-rc.2", "true")]:
        result = subprocess.run([str(SCRIPT), "prepare", tag, prerelease],
                                env=env, capture_output=True, text=True)
        assert result.returncode != 0 and "must be newer" in result.stderr
        assert json.loads(state_path.read_text()) == state

    feed.write_text(appcast(30))
    run("publish", "v1.2.0", failure={"FAIL_AFTER_DELETE": CHANNEL})
    # Once a published channel loses its history, refuse to guess which replay is safe.
    result = subprocess.run([str(SCRIPT), "publish", "v1.0.0", "false"],
                            env=env, capture_output=True, text=True)
    assert result.returncode != 0 and "Cannot verify RC channel history" in result.stderr

print("Release publication tests passed")
