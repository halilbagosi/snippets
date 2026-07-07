import { DSIconButton } from "@snippets/design-system";

function CopyIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.4">
      <rect x="6" y="6" width="9" height="9" rx="1.5" />
      <path d="M3 12V3.5A1.5 1.5 0 0 1 4.5 2H12" />
    </svg>
  );
}

function StarIcon({ filled }: { filled?: boolean }) {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 18 18"
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth="1.4"
    >
      <path d="M9 2.5l2.02 4.1 4.53.66-3.28 3.2.77 4.5L9 12.8l-4.04 2.13.77-4.5-3.28-3.2 4.53-.66L9 2.5z" />
    </svg>
  );
}

function TrashIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.4">
      <path d="M3.5 5h11M7 5V3.5h4V5M4.5 5l.6 9.5a1 1 0 0 0 1 .95h5.8a1 1 0 0 0 1-.95L13.5 5" />
    </svg>
  );
}

export function CopyAction() {
  return <DSIconButton icon={<CopyIcon />} onClick={() => {}} />;
}

export function FavoriteToggle() {
  return <DSIconButton icon={<StarIcon filled />} onClick={() => {}} />;
}

export function DeleteAction() {
  return <DSIconButton icon={<TrashIcon />} onClick={() => {}} />;
}

export function Disabled() {
  return <DSIconButton icon={<TrashIcon />} onClick={() => {}} disabled />;
}
