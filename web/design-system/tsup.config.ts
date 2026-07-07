import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/index.ts"],
  format: ["esm", "cjs"],
  dts: true,
  clean: true,
  sourcemap: false,
  external: ["react", "react-dom"],
  outExtension({ format }) {
    return { js: format === "esm" ? ".es.js" : ".js" };
  },
});
