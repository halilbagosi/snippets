import Foundation

/// Which live-preview engine a snippet's language runs on, if any.
enum PreviewKind: Equatable {
    case web(WebPreviewFlavor)
    case metal
    case swiftUI
}

/// Flavors handled by the WKWebView engine.
enum WebPreviewFlavor: Equatable {
    case html
    case css
    case javascript
    case typescript
    case react
    case glsl
}

extension SupportedLanguage {
    var previewKind: PreviewKind? {
        switch self {
        case .html: return .web(.html)
        case .css: return .web(.css)
        case .javascript: return .web(.javascript)
        case .typescript: return .web(.typescript)
        case .react: return .web(.react)
        case .glsl: return .web(.glsl)
        case .metal: return .metal
        case .swift: return .swiftUI
        case .python, .rust, .go, .kotlin, .hlsl, .json, .cpp, .unknown:
            return nil
        }
    }
}
