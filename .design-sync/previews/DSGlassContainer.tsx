import * as React from "react";
import { DSGlassContainer, DSGlassCard, DSBadge, Color } from "@snippets/design-system";

const backdrop: React.CSSProperties = {
  padding: 24,
  background: "linear-gradient(135deg, #6b8cff 0%, #b46bff 50%, #ff6b9d 100%)",
};

function MiniCard({ title, lang }: { title: string; lang: string }) {
  return (
    <DSGlassCard>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", minWidth: 200 }}>
        <span style={{ fontSize: 15 }}>{title}</span>
        <DSBadge text={lang} color={Color.tint} />
      </div>
    </DSGlassCard>
  );
}

export function Default() {
  return (
    <div style={backdrop}>
      <DSGlassContainer spacing={12}>
        <MiniCard title="debounce.ts" lang="TypeScript" />
        <MiniCard title="retry.swift" lang="Swift" />
        <MiniCard title="deploy.sh" lang="Shell" />
      </DSGlassContainer>
    </div>
  );
}
