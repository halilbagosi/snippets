import * as React from "react";
import { Shadow } from "../tokens/shadow";

export interface DSGlassCardProps {
  children: React.ReactNode;
  /** Optional tint color layered under the glass fill. */
  tint?: string;
  /** @default Shadow.liquidRadius */
  shadowRadius?: number;
  /** @default Shadow.liquidY */
  shadowY?: number;
}

/**
 * Content wrapped in the Liquid Glass surface (blur + translucent fill/border + soft shadow).
 * Ported from Sources/Snippets/DesignSystem/Components/DSGlassCard.swift and
 * Modifiers/DSGlassModifier.swift.
 */
export function DSGlassCard({
  children,
  tint,
  shadowRadius = Shadow.liquidRadius,
  shadowY = Shadow.liquidY,
}: DSGlassCardProps) {
  return (
    <div
      className={`ds-glass-card${tint ? " ds-glass-card--tinted" : ""}`}
      style={
        {
          "--ds-glass-tint-color": tint,
          "--ds-glass-shadow-radius": `${shadowRadius}px`,
          "--ds-glass-shadow-y": `${shadowY}px`,
        } as React.CSSProperties
      }
    >
      {children}
    </div>
  );
}
