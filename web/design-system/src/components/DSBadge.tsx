import * as React from "react";
import { Color } from "../tokens/color";

export interface DSBadgeProps {
  text: string;
  /** CSS color for text + 20%-opacity background tint. @default textPrimary token */
  color?: string;
}

/**
 * Small static status label.
 * Ported from Sources/Snippets/DesignSystem/Components/DSBadge.swift.
 */
export function DSBadge({ text, color = Color.textPrimary }: DSBadgeProps) {
  return (
    <span
      className="ds-badge"
      style={{ color, background: colorMix(color, 0.2) }}
    >
      {text}
    </span>
  );
}

function colorMix(color: string, alpha: number): string {
  return `color-mix(in srgb, ${color} ${alpha * 100}%, transparent)`;
}
