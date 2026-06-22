---
name: Design System Review
triggers:
  - "review the design system"
  - "check for bypassed tokens"
  - "check design system compliance"
  - "find hardcoded styling"
description: "Checks if SwiftUI views use hardcoded styles instead of Design System tokens."
---

# Design System Review

When the user asks to review the design system or check for bypassed tokens, you should scan the codebase to find violations of the Design System.

## Instructions

1. Use `grep` or `rg` to search for hardcoded styling modifiers in `Sources/Snippets/Views` and `Sources/Snippets/Features`.
2. Look specifically for the following hardcoded styles:
    - `.padding(`
    - `.cornerRadius(`
    - `Color.`
    - `.font(`
3. Flag any instances found as violations of the Design System.
4. Suggest using `DSToken` or corresponding `DS` components instead of hardcoded values.
