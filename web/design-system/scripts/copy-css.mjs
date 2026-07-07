import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const distDir = join(root, "dist");
mkdirSync(distDir, { recursive: true });

const tokens = readFileSync(join(root, "src/styles/tokens.css"), "utf8");
const components = readFileSync(join(root, "src/styles/components.css"), "utf8");

writeFileSync(join(distDir, "tokens.css"), tokens);
writeFileSync(join(distDir, "components.css"), components);
// styles.css is the real compiled stylesheet (tokens + component rules
// inlined), not an @import stub — design-sync's cssEntry expects actual CSS.
writeFileSync(join(distDir, "styles.css"), `${tokens}\n${components}\n`);
