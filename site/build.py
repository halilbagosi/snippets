#!/usr/bin/env python3
"""Builds the Snippets document pages (support, privacy, license) into
site/<page>/index.html from one shared shell.

- support and privacy come from site/pages/<page>.html (just the content);
- license is the EULA the app bundles, so Help > License Agreement and the
  website always show the same text.

It also fingerprints style.css, home.css and site.js in every page's links.

The landing page (site/index.html) is written by hand, except for
its header and favicons, which this script fills in between <!-- header -->
and <!-- favicons --> markers so every page shares one nav, and the version
between <!-- version --> markers: the newest release in site/appcast.xml, the
same feed installed copies update from. release.sh runs this after adding a
release to the feed.

It also writes redirect pages at the old /snippets/ paths, where the site
lived before it moved to the root of snippets.halilbagosi.com; older builds
of the app link there. Run after
changing a page fragment, the shell below, or EULA.txt:

    python3 site/build.py
"""

import hashlib
import html
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
EULA = ROOT / "Sources/Snippets/Resources/EULA.txt"

# Where "Support Snippets" sends people.
SPONSOR = "https://github.com/sponsors/halilbagosi"

# The DMG the latest (non-pre-) release in the Pages repo carries.
DOWNLOAD = "https://github.com/halilbagosi/snippetsPage/releases/latest/download/Snippets.dmg"

SHELL = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <title>{title}</title>
  <meta name="description" content="{description}">
  <meta name="theme-color" content="#f5f6f8" media="(prefers-color-scheme: light)">
  <meta name="theme-color" content="#0e1014" media="(prefers-color-scheme: dark)">
{favicons}
  <link rel="stylesheet" href="../style.css">
  <script>try{{var n=navigator;if(/iPhone|iPad|iPod|Android/i.test(n.userAgent))document.documentElement.dataset.device="mobile"}}catch(e){{}}</script>
  <script src="../site.js" defer></script>
</head>
<body>
  <div class="backdrop" aria-hidden="true">
    <div class="glow glow-a"></div>
    <div class="glow glow-b"></div>
  </div>

{header}
  <main class="doc">
    <div class="wrap wrap-narrow">
{body}
    </div>
  </main>

  <footer class="site-footer">
    <div class="wrap">
      <span>© 2026 Halil Bagosi</span>
      <nav aria-label="Footer">
        <a href="../support/">support</a>
        <a href="../privacy/">privacy</a>
        <a href="../license/">license</a>
      </nav>
    </div>
  </footer>
</body>
</html>
"""

PAGES = {
    "support": ("Snippets Support",
                "Get help with Snippets for macOS: answers to common questions and how to contact support."),
    "privacy": ("Privacy Policy · Snippets",
                "Snippets collects no personal data. Your library stays on your Mac unless you connect an AI agent."),
    "license": ("License Agreement · Snippets",
                "The end user licence agreement for Snippets for macOS: free for personal and commercial use."),
}


def favicons(base: str) -> str:
    return (f'  <link rel="icon" href="{base}icon-light.png" media="(prefers-color-scheme: light)">\n'
            f'  <link rel="icon" href="{base}icon-dark.png" media="(prefers-color-scheme: dark)">')


def header(base, current):
    """The nav every page shares. `base` is the path back to the site root."""
    mark = ' aria-current="page"'
    links = f'      <a href="{base}#features">features</a>\n' + "\n".join(
        f'      <a href="{base}{p}/"{mark if p == current else ""}>{p}</a>'
        for p in ("support", "privacy", "license")
    )
    return f"""  <header class="nav glass">
    <a class="brand" href="{base or './'}"><img class="theme-light" src="{base}icon-light.png" alt=""><img class="theme-dark" src="{base}icon-dark.png" alt="">snippets</a>
    <nav class="nav-links" aria-label="Site">
{links}
    </nav>
    <a class="btn btn-glass btn-sponsor" href="{SPONSOR}" target="_blank" rel="noopener"><svg viewBox="0 -.55 16 16" fill="currentColor" aria-hidden="true"><path d="M8 14.2 6.9 13.2C3 9.7.5 7.4.5 4.6.5 2.4 2.2.7 4.4.7c1.2 0 2.5.6 3.6 1.8C9.1 1.3 10.4.7 11.6.7c2.2 0 3.9 1.7 3.9 3.9 0 2.8-2.5 5.1-6.4 8.6z"/></svg><span>Support Snippets</span></a>
    <a class="btn btn-primary" href="{DOWNLOAD}"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M8 2v8.5M4.5 7 8 10.5 11.5 7M3 13.5h10"/></svg><span>download</span></a>
  </header>
"""


def license_body() -> str:
    # One line, newlines as &#10;: the legal block is pre-wrap, so the page
    # indentation applied below must not reach inside it.
    eula = html.escape(EULA.read_text().strip()).replace("\n", "&#10;")
    return f"""<p class="eyebrow reveal">// license</p>
<h1 class="headline reveal">License Agreement</h1>
<p class="lede reveal">Snippets is free to use, at home and at work. This is the agreement you
accept by installing it. The same text is in the app under Help ▸ License Agreement.</p>

<div class="card glass reveal">
  <div class="legal">{eula}</div>
</div>

<p class="reveal">Snippets also includes open-source components under their own MIT licences. The app
lists them under Help ▸ Third-Party Notices.</p>"""


def latest_version() -> str:
    """The shortVersionString of the highest sparkle:version in the appcast."""
    sp = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    items = ET.parse(SITE / "appcast.xml").getroot().iter("item")
    releases = [(int(i.findtext(sp + "version")), i.findtext(sp + "shortVersionString")) for i in items]
    if not releases:
        raise SystemExit("error: site/appcast.xml lists no releases")
    return max(releases)[1].strip()


def indent(text: str, by: str) -> str:
    return "\n".join(by + line if line.strip() else line for line in text.splitlines())


for page, (title, description) in PAGES.items():
    body = license_body() if page == "license" else (SITE / "pages" / f"{page}.html").read_text().rstrip()
    out = SITE / page / "index.html"
    out.write_text(SHELL.format(title=title, description=description, favicons=favicons("../"),
                                  header=header("../", page), body=indent(body, "      ")))
    print(f"wrote {out.relative_to(ROOT)}")

# The hand-written home page gets the same header and favicons, between markers.
home = SITE / "index.html"
text = home.read_text()
for name, block in (("favicons", favicons("") + "\n"), ("header", header("", None))):
    begin, end = f"<!-- {name} -->\n", f"<!-- /{name} -->"
    i, j = text.index(begin) + len(begin), text.index(end)
    text = text[:i] + block + text[j:]
version = latest_version()
text, found = re.subn(r"(<!-- version -->).*?(<!-- /version -->)", rf"\g<1>{version}\g<2>", text)
if not found:
    raise SystemExit(f"error: {home.relative_to(ROOT)} has no <!-- version --> marker")
home.write_text(text)
print(f"wrote {home.relative_to(ROOT)} (header, favicons, version {version})")

# The site used to live under /snippets/ (halilbagosi.github.io/snippets/...,
# which GitHub now redirects to this domain). Older app builds link to those
# paths, so each one forwards to its new home.
REDIRECT = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Snippets</title>
  <meta http-equiv="refresh" content="0; url={to}">
  <link rel="canonical" href="{to}">
  <script>location.replace("{to}" + location.hash)</script>
</head>
<body>
  <p><a href="{to}">Snippets has moved here.</a></p>
</body>
</html>
"""
for old, new in (("", "/"), ("support/", "/support/"), ("privacy/", "/privacy/"), ("license/", "/license/")):
    out = SITE / "snippets" / old / "index.html"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(REDIRECT.format(to=new))
print("wrote redirects under site/snippets/")

# Fingerprint the stylesheets and script in every page (style.css?v=<hash>).
# GitHub Pages tells browsers to keep them for 10 minutes, so without this a
# visitor can get a new page with an old stylesheet. A new hash is a new URL.
assets = {name: hashlib.sha256((SITE / name).read_bytes()).hexdigest()[:10]
          for name in ("style.css", "home.css", "site.js")}
pages = [SITE / "index.html"] + [SITE / p / "index.html" for p in PAGES]
for page in pages:
    text = page.read_text()
    for name, digest in assets.items():
        text = re.sub(rf'({re.escape(name)})(\?v=[0-9a-f]+)?"', rf'\1?v={digest}"', text)
    page.write_text(text)
print("fingerprinted", ", ".join(f"{n}?v={d}" for n, d in assets.items()))
