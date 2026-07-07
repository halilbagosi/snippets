import { DSBadge } from "@snippets/design-system";
import { Color } from "@snippets/design-system";

export function Default() {
  return <DSBadge text="12 snippets" />;
}

export function Tint() {
  return <DSBadge text="New" color={Color.tint} />;
}

export function Destructive() {
  return <DSBadge text="Deprecated" color={Color.destructive} />;
}
