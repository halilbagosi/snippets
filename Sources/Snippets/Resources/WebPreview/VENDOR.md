# Vendored preview runtimes

Every file in this directory is third-party JavaScript or CSS that Snippets
inlines into generated preview documents. They run with `'unsafe-inline'` and
`'unsafe-eval'` in the same frame as the snippet being previewed, so a swapped
file is a swapped preview runtime for every snippet in the library.

They are committed rather than fetched, which is the right call — previews work
offline and no build step reaches the network — but committed blobs are only as
trustworthy as their provenance record. That is what this file is.

## Contents

| File | Package | Version | Source |
|------|---------|---------|--------|
| `react.production.min.js` | react (UMD, production) | 18.3.1 | https://unpkg.com/react@18.3.1/umd/react.production.min.js |
| `react-dom.production.min.js` | react-dom (UMD, production) | 18.3.1 | https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js |
| `babel.min.js` | @babel/standalone | see note | https://unpkg.com/@babel/standalone/babel.min.js |
| `tailwind.browser.min.js` | @tailwindcss/browser | 4.3.3 | https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4 |
| `bootstrap.bundle.min.js` | bootstrap (bundle, Popper included) | 5.3.8 | https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/js/bootstrap.bundle.min.js |
| `bootstrap.min.css` | bootstrap | 5.3.8 | https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/css/bootstrap.min.css |

Versions for react, react-dom, tailwind and bootstrap are read from banners or
version constants inside the files themselves.

**Note on `babel.min.js`:** the bundle carries no unambiguous version banner —
several `7.2x.y` strings appear, belonging to the packages it embeds rather than
to `@babel/standalone` itself. The URLs above are the conventional sources, not
a verified record of where this specific byte sequence came from. To pin it
properly: open any React preview's web inspector, evaluate `Babel.version`,
record the answer here, and re-download from the exact versioned URL so the
checksum below corresponds to a URL anyone can re-fetch.

## Checksums

SHA-256, verified in CI (see `.github/workflows/ci.yml`). Regenerate with:

```bash
shasum -a 256 Sources/Snippets/Resources/WebPreview/*.js Sources/Snippets/Resources/WebPreview/*.css
```

```
19e0d4fb80672e7bacd6e823c7d082954bcad022360e707bc908bfdeb8de08c2  babel.min.js
e4fd49181388c48ec5040bd3fe66f57c29c8e67fcd8502b3354b96ec7ab47cc7  bootstrap.bundle.min.js
d85327d99c7a3ee1f9b5d0500d1370acea3ad2db39c163c2f51f232baedbdede  bootstrap.min.css
35f4f974f4b2bcd44da73963347f8952e341f83909e4498227d4e26b98f66f0d  react-dom.production.min.js
d949f1c3687aedadcedac85261865f29b17cd273997e7f6b2bfc53b2f9d4c4dd  react.production.min.js
6d8c473ef2f8ad63feafc0bd76502dda31501a6c135dc4c6173f6268cde595be  tailwind.browser.min.js
```

## Updating a runtime

1. Download from a versioned URL — never a floating tag like `@4` or `@latest`,
   which makes the checksum unreproducible.
2. Replace the file, update its row and checksum above.
3. Run the test suite: the preview builder tests exercise these runtimes.

A CI checksum failure means a vendored file changed without this record
changing. Treat it as a supply-chain question first and a merge accident second.
