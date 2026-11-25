"""Generate and verify the Sparkle feed for the current GitHub release."""

import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from urllib.parse import quote
import xml.etree.ElementTree as ET
from zipfile import ZipFile


def main():
    root = Path(__file__).resolve().parents[1]
    tools = root / ".build/arm64/artifacts/sparkle/Sparkle/bin"
    dist = root / os.environ.get("OUT_DIR", "dist")
    tag = os.environ["GITHUB_REF_NAME"]
    repository = os.environ["GITHUB_REPOSITORY"]
    release = f"https://github.com/{repository}/releases"
    download = f"{release}/download/{quote(tag, safe='')}/"
    archive = dist / f"CommandDock-{tag[1:]}-universal.zip"
    private_key = os.environ.pop("SPARKLE_PRIVATE_KEY", "").strip()
    if not private_key:
        raise SystemExit("发布更新需要配置 SPARKLE_PRIVATE_KEY。")

    with ZipFile(archive) as package:
        info = plistlib.loads(package.read("CommandDock.app/Contents/Info.plist"))
    if not all(info.get(key) is True for key in ("SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction")):
        raise SystemExit("发布包必须同时启用 Sparkle 清单签名验证和解压前验证。")
    if info["SUPublicEDKey"] != (root / "scripts/sparkle-public-key.txt").read_text().strip():
        raise SystemExit("安装包内的更新公钥与仓库公钥不匹配。")
    if info["SUFeedURL"] != f"{release}/latest/download/appcast.xml":
        raise SystemExit("安装包内的更新地址与当前仓库不匹配。")

    def run_tool(name, *args):
        subprocess.run([tools / name, "--ed-key-file", "-", *args],
                       input=private_key, text=True, check=True)

    with tempfile.TemporaryDirectory() as directory:
        stage = Path(directory)
        shutil.copy2(archive, stage)
        notes = root / ".github/release-notes" / f"{tag}.md"
        if notes.is_file():
            shutil.copy2(notes, stage / (archive.stem + ".md"))
        feed = stage / "appcast.xml"
        run_tool("generate_appcast", "--download-url-prefix", download, "--embed-release-notes",
                 "--link", f"{release}/tag/{quote(tag, safe='')}", "-o", feed, stage)

        enclosure = ET.parse(feed).find("./channel/item/enclosure")
        namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
        if enclosure is None or enclosure.get("url") != download + quote(archive.name):
            raise SystemExit("更新清单缺少当前发布包的下载地址。")
        signature = enclosure.get(namespace + "edSignature")
        if not signature or enclosure.get("length") != str(archive.stat().st_size):
            raise SystemExit("更新包签名或长度无效，请检查发布私钥是否匹配应用公钥。")
        run_tool("sign_update", "--verify", archive, signature)
        run_tool("sign_update", "--verify", feed)
        shutil.copy2(feed, dist / feed.name)


if __name__ == "__main__":
    main()
