import * as React from "react";
import { DSGlassCard, DSBadge, Color } from "@snippets/design-system";

const backdrop: React.CSSProperties = {
  padding: 24,
  background: "linear-gradient(135deg, #6b8cff 0%, #b46bff 50%, #ff6b9d 100%)",
};

function SnippetPreview() {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8, minWidth: 220 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <strong style={{ fontSize: 15 }}>debounce.ts</strong>
        <DSBadge text="TypeScript" color={Color.tint} />
      </div>
      <pre style={{ margin: 0, fontSize: 12, opacity: 0.8, fontFamily: "monospace" }}>
        {"function debounce(fn, ms) {\n  let t;\n  return (...a) => {\n    clearTimeout(t);\n    t = setTimeout(() => fn(...a), ms);\n  };\n}"}
      </pre>
    </div>
  );
}

export function Default() {
  return (
    <div style={backdrop}>
      <DSGlassCard>
        <SnippetPreview />
      </DSGlassCard>
    </div>
  );
}

export function Tinted() {
  return (
    <div style={backdrop}>
      <DSGlassCard tint={Color.tint}>
        <SnippetPreview />
      </DSGlassCard>
    </div>
  );
}
