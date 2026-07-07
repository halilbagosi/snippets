import { DSTag } from "@snippets/design-system";

export function Unselected() {
  return <DSTag title="Swift" isSelected={false} />;
}

export function Selected() {
  return <DSTag title="JavaScript" isSelected />;
}

export function FilterRow() {
  return (
    <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
      <DSTag title="All" isSelected />
      <DSTag title="Swift" isSelected={false} />
      <DSTag title="Python" isSelected={false} />
      <DSTag title="Shell" isSelected={false} />
    </div>
  );
}
