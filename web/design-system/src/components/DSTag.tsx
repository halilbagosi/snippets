import * as React from "react";

export interface DSTagProps {
  title: string;
  isSelected: boolean;
  onClick?: () => void;
}

/**
 * Toggle-style filter pill.
 * Ported from Sources/Snippets/DesignSystem/Components/DSTag.swift.
 */
export function DSTag({ title, isSelected, onClick = () => {} }: DSTagProps) {
  return (
    <button
      type="button"
      className={`ds-tag${isSelected ? " ds-tag--selected" : ""}`}
      onClick={onClick}
    >
      {title}
    </button>
  );
}
