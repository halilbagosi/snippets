import * as React from "react";

export interface DSGlassContainerProps {
  spacing: number;
  children: React.ReactNode;
}

/**
 * Groups glass surfaces so adjacent ones can morph/merge (native `GlassEffectContainer`
 * on macOS 26+). On the web this is a plain spaced flex column — the merge effect
 * has no CSS equivalent, so it renders as separate cards with matching gaps.
 * Ported from Sources/Snippets/DesignSystem/Components/DSGlassContainer.swift.
 */
export function DSGlassContainer({ spacing, children }: DSGlassContainerProps) {
  return (
    <div className="ds-glass-container" style={{ gap: `${spacing}px` }}>
      {children}
    </div>
  );
}
