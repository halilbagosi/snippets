import { Color } from "./color";
import { Spacing } from "./spacing";
import { Radius } from "./radius";
import { Shadow } from "./shadow";
import { Typography } from "./typography";

export { Color, Spacing, Radius, Shadow, Typography };

/** Mirrors Swift's `DSToken` namespace (`Sources/Snippets/DesignSystem/Tokens/DSToken.swift`). */
export const DSToken = { Color, Spacing, Radius, Shadow, Typography } as const;
