import * as React from "react";

export interface DSIconButtonProps {
  /**
   * Icon content. The Swift original takes an SF Symbol name string; the web
   * has no SF Symbol renderer, so this takes the rendered icon node instead
   * (an inline SVG, an icon-font glyph, etc).
   */
  icon: React.ReactNode;
  onClick: () => void;
  disabled?: boolean;
}

/**
 * Borderless icon button that fills on hover.
 * Ported from Sources/Snippets/DesignSystem/Components/DSIconButton.swift.
 */
export function DSIconButton({ icon, onClick, disabled }: DSIconButtonProps) {
  return (
    <button type="button" className="ds-icon-button" onClick={onClick} disabled={disabled}>
      {icon}
    </button>
  );
}
