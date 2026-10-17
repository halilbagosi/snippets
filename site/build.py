#!/usr/bin/env python3
"""Regenerates site/snippets/license/index.html from the EULA the app bundles.

The app's Help > License Agreement and the website must show the same text,
so the page is generated rather than edited by hand. Run after changing
Sources/Snippets/Resources/EULA.txt:

    python3 site/build.py
"""

import html
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EULA = ROOT / "Sources/Snippets/Resources/EULA.txt"
PAGE = ROOT / "site/snippets/license/index.html"

TEMPLATE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>License Agreement · Snippets</title>
  <meta name="description" content="The end user licence agreement for Snippets for macOS: free for personal and commercial use.">
  <link rel="icon" href="../icon.png">
  <link rel="stylesheet" href="../style.css">
</head>
<body>
  <header class="site-header">
    <div class="wrap">
      <a class="brand" href="../"><img src="../icon.png" alt="">Snippets</a>
      <nav class="site-nav">
        <a href="../support/">Support</a>
        <a href="../privacy/">Privacy</a>
        <a href="../license/" aria-current="page">License</a>
      </nav>
    </div>
  </header>

  <main>
    <div class="wrap">
      <h1>License Agreement</h1>
      <p class="lede">Snippets is free to use, at home and at work. This is the agreement you
      accept by installing it. The same text is in the app under Help ▸ License Agreement.</p>

      <div class="card">
        <div class="legal">{eula}</div>
      </div>

      <p>Snippets also includes open-source components under their own MIT licences. The app
      lists them under Help ▸ Third-Party Notices.</p>
    </div>
  </main>

  <footer class="site-footer">
    <div class="wrap">
      <span>© 2026 Halil Bagosi</span>
      <nav>
        <a href="../support/">Support</a>
        <a href="../privacy/">Privacy</a>
        <a href="../license/">License</a>
      </nav>
    </div>
  </footer>
</body>
</html>
"""

PAGE.write_text(TEMPLATE.replace("{eula}", html.escape(EULA.read_text().strip())))
print(f"wrote {PAGE.relative_to(ROOT)}")
