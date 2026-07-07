import { DSButton } from "@snippets/design-system";

export function Primary() {
  return <DSButton title="Save Snippet" onClick={() => {}} />;
}

export function Secondary() {
  return <DSButton title="Cancel" style="secondary" onClick={() => {}} />;
}

export function Ghost() {
  return <DSButton title="Show More" style="ghost" onClick={() => {}} />;
}

export function Destructive() {
  return <DSButton title="Delete Snippet" style="destructive" onClick={() => {}} />;
}

export function Disabled() {
  return <DSButton title="Save Snippet" onClick={() => {}} disabled />;
}
