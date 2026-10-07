#!/usr/bin/env python3
"""Download 1C platform distributions from releases.1c.ru (headless).

Usage (run from the repo root):
    python3 src/scripts/fetch-release.py --list 8.5.4.1878
    python3 src/scripts/fetch-release.py 8.5.4.1878                # standard set
    python3 src/scripts/fetch-release.py 8.5.4.1878 --files 'server.arm.deb64*,macos.client.arm64*'

The standard set mirrors what the 8.3/8.5 stands are built from:
    server.arm.deb64_<v>.zip   -> unzipped into dists/ (common + server debs)
    client.arm.deb64_<v>.zip   -> unzipped into dists/ (client deb, lic stand)
    macos.client.arm64_<v>.dmg -> dists/ (native Apple Silicon client)
    checksums_<v>.zip          -> dists/

URL scheme (learned 2026-10-07):
    listing  https://releases.1c.ru/version_files?nick=Platform85&ver=<v>
    download https://releases.1c.ru/version_file?nick=Platform85&ver=<v>&path=Platform%5C<ver_us>%5C<file>
    catalog of all projects: https://releases.1c.ru/total
    path prefix "Platform" + "\\" + "<ver with _ instead of .>" + "\\" + "<file>", backslashes %5C.

Auth: login.1c.ru is a Spring WebFlow form. POST username/password plus the
hidden execution/_eventId from the login page; anotherComputer/rememberMe MUST
be real booleans (an empty string triggers a typeMismatch and the login fails
with a misleading "Неверный логин или пароль"). Credentials are read from .env:
    RELEASES_LOGIN / RELEASES_PASSWORD     (the downloads-only account)
with DEV_LICENSE_LOGIN/DEV_LICENSE_PASSWORD as a fallback (it logs in but sees
no files). Only stdlib is used — no deps, nothing installed on the host.
"""

import argparse
import os
import re
import shutil
import sys
import urllib.parse
import urllib.request
import http.cookiejar
import zipfile

BASE = "https://releases.1c.ru"
NICK = "Platform85"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"


def read_env(path=".env"):
    env = {}
    if os.path.exists(path):
        for line in open(path):
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                env[k] = v
    return env


class Releases:
    def __init__(self, login, password):
        self.jar = http.cookiejar.CookieJar()
        self.op = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar))
        self.op.addheaders = [("User-Agent", UA)]
        self.login, self.password = login, password

    def _page(self, url):
        r = self.op.open(url)
        return r.read().decode("utf-8", "replace"), r.geturl()

    def authed_get(self, url):
        """GET with login on first use; returns (html, final_url)."""
        page, final = self._page(url)
        if "login.1c.ru" not in final:
            return page, final
        form = next(f for f in re.findall(r"<form[^>]*>.*?</form>", page, re.S)
                    if re.search(r'type="password"', f))
        action = re.search(r'action="([^"]*)"', form).group(1)
        data = {}
        for inp in re.findall(r"<input[^>]+>", form):
            n = re.search(r'name="([^"]+)"', inp)
            v = re.search(r'value="([^"]*)"', inp)
            if n and n.group(1) in ("execution", "_eventId"):
                data[n.group(1)] = v.group(1) if v else ""
        data.update({
            "username": self.login,
            "password": self.password,
            "_eventId": data.get("_eventId") or "submit",
            "anotherComputer": "false",   # real values, NOT "" (see docstring)
            "rememberMe": "false",
        })
        post_url = urllib.parse.urljoin(final, action)
        if "service=" not in post_url:
            post_url += ("&" if "?" in post_url else "?") + final.split("?", 1)[1]
        r = self.op.open(urllib.request.Request(
            post_url, data=urllib.parse.urlencode(data).encode(),
            headers={"Content-Type": "application/x-www-form-urlencoded",
                     "Referer": final}))
        after = r.read().decode("utf-8", "replace")
        if "Неверный логин" in after:
            raise SystemExit("login rejected (Неверный логин или пароль)")
        return self._page(url)

    def list_files(self, ver, nick=NICK):
        """[(name, download_url)] for a version page."""
        url = f"{BASE}/version_files?nick={nick}&ver={ver}"
        page, final = self.authed_get(url)
        if "login.1c.ru" in final:
            raise SystemExit("still unauthenticated after login — no access?")
        out = []
        for href in re.findall(r'href="(/version_file\?[^"]+)"', page):
            q = urllib.parse.parse_qs(urllib.parse.urlsplit(urllib.parse.urljoin(BASE, href)).query)
            path = q.get("path", [""])[0]
            name = path.replace("\\", "/").rsplit("/", 1)[-1]
            if name:
                dl = (f"{BASE}/version_file?nick={nick}&ver={ver}"
                      f"&path={urllib.parse.quote(path)}")
                out.append((name, dl))
        return out

    def download(self, url, dest):
        # version_file is an interstitial page: parse the real mirror links
        # (https://dl0X.1c.ru/public/file/get/<guid>) plus size/sha512 from it.
        r = self.op.open(url)
        head = r.read(65536)
        is_html = head.lstrip()[:15].lower().startswith((b"<!doctype", b"<html"))
        page_bytes = b""
        if is_html:
            page_bytes = head + r.read()
            mirrors = re.findall(r'https://dl\d+\.1c\.ru/public/file/get/[0-9a-f-]+',
                                 page_bytes.decode("utf-8", "replace"))
            m_sha = re.search(r'SHA-512:\s*([0-9a-f]{128})',
                              page_bytes.decode("utf-8", "replace"))
            m_size = re.search(r'\(([\d\s ]+) байт\)',
                               page_bytes.decode("utf-8", "replace"))
            sha_expect = m_sha.group(1) if m_sha else None
            size_expect = int(m_size.group(1).replace('\xa0', '').replace(' ', '')) \
                if m_size else 0
            if not mirrors:
                open(dest + ".html", "wb").write(page_bytes)
                raise SystemExit(f"no download mirrors on the interstitial page "
                                 f"(saved {dest}.html) — no access for this account?")
            print(f"  mirrors: {len(mirrors)}, size {size_expect>>20} MiB"
                  + (f", sha512 {sha_expect[:12]}…" if sha_expect else ""))
            r.close()
            for m in mirrors:
                try:
                    rr = self.op.open(m)
                    break
                except urllib.error.URLError as e:
                    print(f"  mirror {m.split('/')[2]} failed: {e}")
            else:
                raise SystemExit("all mirrors failed")
        else:
            rr, sha_expect, size_expect = r, None, 0

        import hashlib
        sha = hashlib.sha512()
        total = int(rr.headers.get("Content-Length") or size_expect)
        done = 0
        with open(dest, "wb") as f:
            if not page_bytes:          # binary stream: its head is already read
                f.write(head)
                sha.update(head)
                done = len(head)
            while True:
                chunk = rr.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
                sha.update(chunk)
                done += len(chunk)
                if total:
                    print(f"\r  {os.path.basename(dest)}: {done>>20}/{total>>20} MiB "
                          f"({100*done//total}%)", end="", flush=True)
        print()
        if size_expect and done != size_expect:
            raise SystemExit(f"{dest}: size {done} != expected {size_expect}")
        if sha_expect and sha.hexdigest() != sha_expect:
            raise SystemExit(f"{dest}: SHA-512 mismatch")
        print(f"  ok: {done>>20} MiB"
              + (", sha512 verified" if sha_expect else ""))
        return dest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("version")
    ap.add_argument("--nick", default=NICK)
    ap.add_argument("--files", help="comma-separated glob patterns; default = standard set")
    ap.add_argument("--list", action="store_true", help="only print the file list")
    ap.add_argument("--no-unzip", action="store_true")
    args = ap.parse_args()

    env = read_env(os.path.join(os.path.dirname(__file__), "..", "..", ".env"))
    login = env.get("RELEASES_LOGIN") or env.get("DEV_LICENSE_LOGIN")
    password = env.get("RELEASES_PASSWORD") or env.get("DEV_LICENSE_PASSWORD")
    if not login:
        raise SystemExit("no RELEASES_LOGIN/DEV_LICENSE_LOGIN in .env")

    rel = Releases(login, password)
    files = rel.list_files(args.version, args.nick)
    if not files:
        raise SystemExit("version page has no files (no access for this account?)")
    print(f"{len(files)} files on the version page:")
    for name, _ in files:
        print("  ", name)
    if args.list:
        return

    default = ["server.arm.deb64_*", "client.arm.deb64_*",
               "macos.client.arm64_*", "checksums_*"]
    patterns = [p.strip() for p in (args.files or ",".join(default)).split(",")]
    import fnmatch
    picked = [(n, u) for n, u in files
              if any(fnmatch.fnmatch(n, p) for p in patterns)]
    if not picked:
        raise SystemExit(f"nothing matches {patterns}")
    print("downloading:")
    for n, _ in picked:
        print("  ", n)

    dists = os.path.join(os.path.dirname(__file__), "..", "..", "dists")
    os.makedirs(dists, exist_ok=True)
    for name, url in picked:
        dest = os.path.join(dists, name)
        if os.path.exists(dest):
            with open(dest, "rb") as f:
                first = f.read(200)
            if first.lstrip()[:15].lower().startswith((b"<!doctype", b"<html")):
                os.remove(dest)            # garbage from an earlier HTML answer
            else:
                print(f"  {name}: already in dists/, skip")
                continue
        rel.download(url, dest)

    if not args.no_unzip:
        for name, _ in picked:
            if name.endswith(".zip") and not name.startswith("checksums"):
                zpath = os.path.join(dists, name)
                with zipfile.ZipFile(zpath) as z:
                    for m in z.namelist():
                        if m.endswith(".deb"):
                            out = os.path.join(dists, os.path.basename(m))
                            if not os.path.exists(out):
                                with z.open(m) as src, open(out, "wb") as dst:
                                    shutil.copyfileobj(src, dst)
                                print(f"  unpacked {os.path.basename(out)}")
                print(f"  (archive kept: {name})")


if __name__ == "__main__":
    main()
