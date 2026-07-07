import * as React from "react";

export type DSButtonStyle = "primary" | "secondary" | "ghost" | "destructive";

export interface DSButtonProps {
  /** Button label. */
  title: string;
  /** Visual style. @default "primary" */
  style?: DSButtonStyle;
  /** Called when the button is activated. */
  onClick: () => void;
  disabled?: boolean;
}

/**
 * Full-width action button with four visual styles.
 * Ported from Sources/Snippets/DesignSystem/Components/DSButton.swift.
 */
export function DSButton({ title, style = "primary", onClick, disabled }: DSButtonProps) {
  return (
    <button
      type="button"
      className={`ds-button ds-button--${style}`}
      onClick={onClick}
      disabled={disabled}
    >
      {title}
    </button>
  );
}
