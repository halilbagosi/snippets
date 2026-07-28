import Foundation

// Evidence tables for `LanguageDetector`. Split out from the detection
// algorithm so the pattern lists can grow without burying the pipeline.

extension LanguageDetector {

    /// How much a single marker is worth. A language needs `minimumConfidence`
    /// to be claimed at all, so one `.decisive` marker is enough on its own
    /// while a pile of `.weak` ones is not.
    enum Weight {
        /// Effectively unique to one language (`#include <metal_stdlib>`).
        static let decisive = 6.0
        /// Rare outside the language, but imitable (`err != nil`).
        static let strong = 3.0
        /// Idiomatic, shared with a handful of relatives (`const x`).
        static let medium = 1.5
        /// Suggestive only (`mix(`, `nil`).
        static let weak = 0.6
    }

    static let profiles: [Profile] = [
        shaderProfiles,
        appleProfiles,
        systemsProfiles,
        webProfiles
    ].flatMap { $0 }

    // MARK: - Shaders

    private static var shaderProfiles: [Profile] {
        [
            Profile(language: .glsl, markers: [
                marker(#"(?m)^\s*#version\s+\d"#, Weight.decisive),
                marker(#"\bgl_(FragColor|Position|FragCoord|PointSize|VertexID|PointCoord)\b"#, Weight.decisive, cap: 2),
                marker(#"(?m)^\s*precision\s+(lowp|mediump|highp)\s+"#, Weight.decisive),
                marker(#"(?m)^\s*(uniform|varying|attribute)\s+(float|int|bool|vec[234]|mat[234]|sampler2D|samplerCube)\b"#, Weight.strong, cap: 3),
                marker(#"(?m)^\s*(out|in)\s+(vec[234]|float)\s+\w+\s*;"#, Weight.strong, cap: 2),
                marker(#"\bmainImage\s*\(\s*out\s+vec4"#, Weight.decisive),
                marker(#"\bi(Resolution|Time|Mouse|TimeDelta|Frame)\b"#, Weight.strong, cap: 2),
                marker(#"\btexture(2D|Cube|Lod)\s*\("#, Weight.strong),
                marker(#"\bvec[234]\s*\("#, Weight.medium, cap: 3),
                marker(#"\b(fragColor|vUv|vUV|uTime|uResolution)\b"#, Weight.medium, cap: 3),
                marker(#"\bvoid\s+main\s*\(\s*(void)?\s*\)"#, Weight.medium),
                marker(#"\b(smoothstep|fract|mix|clamp|normalize|dot|length)\s*\("#, Weight.weak, cap: 4)
            ]),

            Profile(language: .metal, markers: [
                marker(#"#include\s*<metal_stdlib>"#, Weight.decisive),
                marker(#"\busing\s+namespace\s+metal\b"#, Weight.decisive),
                marker(#"\[\[\s*(stage_in|position|buffer|texture|sampler|point_size|vertex_id|instance_id|thread_position_in_grid|threadgroup_position_in_grid|color)\b"#, Weight.decisive, cap: 3),
                marker(#"(?m)^\s*(fragment|vertex|kernel)\s+\w"#, Weight.strong, cap: 3),
                marker(#"\btexture(1d|2d|3d|cube)\s*<"#, Weight.strong),
                marker(#"\baccess::(read|write|sample|read_write)\b"#, Weight.strong, cap: 2),
                marker(#"\bmetal::"#, Weight.strong),
                marker(#"\b(constant|device|threadgroup)\s+\w+\s*[&*]"#, Weight.strong, cap: 2),
                marker(#"\bhalf[234]?\b"#, Weight.medium, cap: 2),
                marker(#"\bfloat[234]\s*\("#, Weight.weak, cap: 3)
            ]),

            Profile(language: .hlsl, markers: [
                marker(#"(?i)\bSV_(Position|Target|Depth|VertexID|InstanceID|DispatchThreadID|GroupID)\b"#, Weight.decisive, cap: 3),
                marker(#"(?m)^\s*cbuffer\s+\w"#, Weight.decisive),
                marker(#"\bregister\s*\(\s*[bstu]\d"#, Weight.decisive, cap: 3),
                marker(#"\bSamplerComparisonState\b|\bSamplerState\b"#, Weight.decisive),
                marker(#"\[numthreads\s*\("#, Weight.decisive),
                marker(#"\b(Texture|RWTexture|StructuredBuffer|RWStructuredBuffer)\w*\s*(<[^>\n]*>)?\s+\w"#, Weight.strong, cap: 2),
                marker(#":\s*(TEXCOORD|POSITION|NORMAL|COLOR|TANGENT|BINORMAL)\d*\b"#, Weight.strong, cap: 3),
                marker(#"\bfloat[234]x[234]\b"#, Weight.strong, cap: 2),
                marker(#"\.Sample(Level|Cmp)?\s*\("#, Weight.medium, cap: 2)
            ])
        ]
    }

    // MARK: - Apple platforms

    private static var appleProfiles: [Profile] {
        [
            Profile(language: .swift, markers: [
                marker(#"(?m)^\s*import\s+(SwiftUI|Foundation|UIKit|AppKit|Combine|SwiftData|Observation|CoreGraphics|CoreData|Metal|MetalKit|OSLog|XCTest|Testing)\b"#, Weight.decisive, cap: 2),
                marker(#"\bsome\s+View\b"#, Weight.decisive, cap: 2),
                marker(#"#Preview\b"#, Weight.decisive),
                marker(#"@(State|Binding|Observable|MainActor|Environment|EnvironmentObject|Published|StateObject|ObservedObject|AppStorage|escaping|ViewBuilder|Sendable|available|objc|Model|Query)\b"#, Weight.strong, cap: 3),
                marker(#"(?m)^\s*((public|private|internal|fileprivate|open)\s+)?((final|static|class|override|mutating|nonisolated|@\w+)\s+)*func\s+\w+\s*[(<]"#, Weight.strong, cap: 3),
                marker(#"\bguard\s+(let\s|var\s|!|\w+\s*[!=<>])"#, Weight.strong, cap: 2),
                marker(#"\b(private|public|internal|fileprivate)\s+(var|let|func|class|struct|init|enum)\b"#, Weight.strong, cap: 3),
                marker(#"\bif\s+let\s+\w"#, Weight.strong, cap: 2),
                marker(#"(?m)^\s*(final\s+)?(class|struct|enum|extension|protocol|actor)\s+\w+\s*[:{<]"#, Weight.medium, cap: 3),
                marker(#"\blet\s+\w+\s*(:\s*[A-Z\[]|=)"#, Weight.medium, cap: 3),
                marker(#"\?\?\s|\bnil\s*\)|\.self\b"#, Weight.medium, cap: 2),
                marker(#"->\s*(Void|Self|Never)\b|\(\s*\)\s*->"#, Weight.medium, cap: 2),
                marker(#"\bself\.\w"#, Weight.weak, cap: 2)
            ]),

            Profile(language: .kotlin, markers: [
                marker(#"(?m)^\s*import\s+(kotlin|kotlinx|androidx|android|java)\."#, Weight.decisive, cap: 2),
                marker(#"\bdata\s+class\s+\w"#, Weight.decisive),
                marker(#"\bcompanion\s+object\b"#, Weight.decisive),
                marker(#"\b(suspend|override|inline|operator|private|internal)\s+fun\b"#, Weight.decisive, cap: 2),
                marker(#"\bconst\s+val\b"#, Weight.decisive),
                marker(#"\bfun\s+\w+\s*[(<]"#, Weight.strong, cap: 3),
                marker(#"\b(mutableMapOf|mutableListOf|listOf|mapOf|setOf|arrayOf)\s*[(<]"#, Weight.strong, cap: 2),
                marker(#"(?m)^\s*package\s+[a-z][\w.]*\s*$"#, Weight.strong),
                marker(#"(?m)^\s*object\s+\w+\s*[{:]"#, Weight.strong),
                marker(#"\b(val|var)\s+\w+\s*(:\s*\w|=)"#, Weight.medium, cap: 3),
                marker(#"\?:\s|\?\.\w|!!\B"#, Weight.medium, cap: 2),
                marker(#"\bprintln\s*\(|\bwhen\s*[({]"#, Weight.medium, cap: 2)
            ])
        ]
    }

    // MARK: - Systems / scripting

    private static var systemsProfiles: [Profile] {
        [
            Profile(language: .rust, markers: [
                marker(#"\blet\s+mut\s+\w"#, Weight.decisive),
                marker(#"#\[(derive|cfg|allow|test|tokio|serde|repr|inline|non_exhaustive)"#, Weight.decisive, cap: 3),
                marker(#"\bimpl(<[^>\n]*>)?\s+\w+"#, Weight.decisive, cap: 2),
                marker(#"&mut\s+\w|&'\w+\s"#, Weight.decisive, cap: 2),
                marker(#"(?m)^\s*(pub\s+)?use\s+[a-z_][\w:]*(::[\w:*{}, ]+)?;"#, Weight.strong, cap: 3),
                marker(#"\bfn\s+\w+\s*[(<]"#, Weight.strong, cap: 3),
                marker(#"\b\w+!\s*[(\[]"#, Weight.strong, cap: 3),
                marker(#"->\s*(Self|Result<|Option<|impl\s|&?\w+<)"#, Weight.strong, cap: 2),
                marker(#"\b&str\b|\bString::from\b|::new\(\)"#, Weight.strong, cap: 2),
                marker(#"\bpub\s+(fn|struct|enum|mod|trait|const|use)\b"#, Weight.medium, cap: 3),
                marker(#"\.(unwrap|expect|iter|collect|to_string|as_str)\s*\("#, Weight.medium, cap: 3),
                marker(#"\bmatch\s+[\w.&*]+\s*\{"#, Weight.medium, cap: 2)
            ]),

            Profile(language: .go, markers: [
                marker(#"(?m)^\s*package\s+main\s*$"#, Weight.decisive),
                marker(#"(?m)^\s*import\s+\("#, Weight.decisive),
                marker(#"\berr\s*(!=|==)\s*nil\b"#, Weight.decisive, cap: 2),
                marker(#"(?m)^\s*type\s+\w+\s+(struct|interface)\s*\{"#, Weight.decisive, cap: 2),
                marker(#"\bchan\s+\w|\bgo\s+func\b|\bselect\s*\{"#, Weight.decisive, cap: 2),
                marker(#"\bfmt\.[A-Z]\w*\s*\("#, Weight.decisive, cap: 2),
                marker(#"(?m)^\s*func\s+(\(\s*\w+\s+\*?\w+\s*\)\s*)?\w+\s*\("#, Weight.strong, cap: 3),
                marker(#":=\s*\S"#, Weight.strong, cap: 3),
                marker(#"\bdefer\s+\w|\binterface\{\}|\bstruct\{\}"#, Weight.strong, cap: 2),
                marker(#"(?m)^\s*package\s+\w+\s*$"#, Weight.strong),
                marker(#"\b(http|strings|strconv|errors|context|sync|time|os)\.[A-Z]\w*"#, Weight.medium, cap: 3),
                marker(#"\bnil\b"#, Weight.weak, cap: 3)
            ]),

            Profile(language: .python, markers: [
                marker(#"(?m)^#!.*\bpython"#, Weight.decisive),
                marker(#"\bif\s+__name__\s*==|\b__init__\s*\(self|\b__main__\b"#, Weight.decisive, cap: 2),
                marker(#"(?m)^\s*def\s+\w+\s*\("#, Weight.decisive, cap: 3),
                marker(#"(?m)^\s*class\s+\w+(\([\w., ]*\))?\s*:\s*$"#, Weight.decisive),
                marker(#"\belif\b|(?m)^\s*(async\s+)?with\s+.+:\s*$"#, Weight.decisive, cap: 2),
                marker(#"(?m)^\s*(from\s+[\w.]+\s+)?import\s+[a-z_][\w.,* ]*$"#, Weight.strong, cap: 3),
                marker(#"->\s*(None|int|str|float|bool|bytes|List|Dict|Tuple|Optional|Any)\b"#, Weight.strong, cap: 2),
                marker(#"(?m)^\s*@[\w.]+\s*(\([^)\n]*\))?\s*$"#, Weight.strong, cap: 2),
                marker(#"\blambda\s+\w*\s*:|\braise\s+\w+Error\b"#, Weight.strong, cap: 2),
                marker(#"\bself\.\w"#, Weight.medium, cap: 3),
                marker(#"(?m)^\s*(if|for|while|try|except|else)\b[^\n]*:\s*$"#, Weight.medium, cap: 3),
                marker(#"\b(True|False|None)\b"#, Weight.medium, cap: 3),
                marker(#"\bprint\s*\(|\bf["']"#, Weight.medium, cap: 2)
            ]),

            Profile(language: .cpp, markers: [
                marker(#"\bstd::\w"#, Weight.decisive, cap: 3),
                marker(#"(?m)^\s*template\s*<"#, Weight.decisive, cap: 2),
                marker(#"(?m)^\s*(public|private|protected)\s*:\s*$"#, Weight.decisive, cap: 3),
                marker(#"\bint\s+main\s*\("#, Weight.decisive),
                marker(#"\bnullptr\b|\bconst\s+\w+&\s*\w|\boperator\s*[=+\-<>\[]"#, Weight.strong, cap: 2),
                marker(#"(?m)^\s*#include\s*[<"][\w./]+[>"]"#, Weight.strong, cap: 3),
                marker(#"(?m)^\s*#(define|ifndef|ifdef|pragma|endif)\b"#, Weight.strong, cap: 2),
                marker(#"\busing\s+namespace\s+\w|\bnamespace\s+\w+\s*\{"#, Weight.strong, cap: 2),
                marker(#"\b(printf|malloc|free|sizeof|memcpy)\s*\("#, Weight.strong, cap: 2),
                marker(#"\b(uint8_t|uint32_t|int32_t|int64_t|size_t)\b"#, Weight.medium, cap: 2),
                marker(#"(?m)^\s*(class|struct)\s+\w+\s*(:\s*(public|private)\s+\w+\s*)?\{"#, Weight.medium, cap: 2)
            ])
        ]
    }

    // MARK: - Web

    private static var webProfiles: [Profile] {
        [
            Profile(language: .react, markers: [
                marker(#"\bfrom\s+['"]react(-dom)?(/\w+)?['"]"#, Weight.decisive, cap: 2),
                marker(#"\bimport\s+React\b|\bReactDOM\b|\bcreateRoot\s*\("#, Weight.decisive, cap: 2),
                marker(#"\buse(State|Effect|Ref|Memo|Callback|Context|Reducer|LayoutEffect|ImperativeHandle|Id|Transition|SyncExternalStore)\s*(<[^>\n]*>)?\s*\("#, Weight.decisive, cap: 4),
                marker(#"\bclassName\s*=\s*[{"']"#, Weight.decisive, cap: 3),
                marker(#"\bon[A-Z]\w+\s*=\s*\{"#, Weight.decisive, cap: 3),
                marker(#"(?:^|[\s({,=>])<[A-Z](?=[A-Za-z0-9]*[a-z])[A-Za-z0-9]*(?:\s|/>|>)"#, Weight.decisive, cap: 3),
                marker(#"\bJSX\.Element\b|\bReact\.(FC|ReactNode|Component|memo|forwardRef)\b"#, Weight.decisive),
                marker(#"\breturn\s*\(\s*\n?\s*<"#, Weight.decisive),
                marker(#"</>|<>\s*$"#, Weight.decisive),
                marker(#"\{\s*/\*"#, Weight.decisive),
                marker(#"\buse[A-Z]\w*\s*(<[^>\n]*>)?\s*\("#, Weight.strong, cap: 3),
                // JSX attribute braces. No spaces around `=`, which is
                // universal in JSX and keeps TOML inline tables (`dep = { … }`)
                // and shell brace expansion from reading as components.
                marker(#"<[\w.]+[^<>\n]*\s\w+=\{"#, Weight.strong, cap: 4),
                marker(#"\{children\}|\bprops\.\w|\bdangerouslySetInnerHTML\b"#, Weight.strong, cap: 2),
                marker(#"\bstyled\.\w+|\bkey\s*=\s*\{"#, Weight.strong, cap: 2)
            ]),

            Profile(language: .typescript, markers: [
                marker(#"(?m)^\s*(export\s+)?(declare\s+)?interface\s+\w"#, Weight.decisive, cap: 2),
                marker(#"(?m)^\s*(export\s+)?type\s+\w+(<[^>\n]*>)?\s*="#, Weight.decisive, cap: 2),
                marker(#"\bas\s+const\b|\bsatisfies\s+\w|(?m)^\s*import\s+type\s"#, Weight.decisive, cap: 2),
                marker(#":\s*(string|number|boolean|void|any|unknown|never|symbol|bigint)\b"#, Weight.strong, cap: 4),
                marker(#"\bPromise\s*<|\bRecord\s*<|\bPartial\s*<|\bReadonly\s*<"#, Weight.strong, cap: 2),
                marker(#"\b(public|private|protected|readonly)\s+\w+\s*[:(?]"#, Weight.strong, cap: 3),
                marker(#"\bimplements\s+\w|(?m)^\s*(export\s+)?(const\s+)?enum\s+\w+\s*\{"#, Weight.strong, cap: 2),
                marker(#"\?\s*:\s*[\w<]|!\s*[.;)]"#, Weight.medium, cap: 3),
                marker(#":\s*[A-Z]\w*(\[\])?\s*[=,;)>]"#, Weight.medium, cap: 3),
                marker(#"\)\s*:\s*[\w<>\[\]|]+\s*[{;]"#, Weight.medium, cap: 3)
            ]),

            Profile(language: .javascript, markers: [
                marker(#"\bmodule\.exports\b|\bexports\.\w+\s*="#, Weight.decisive),
                marker(#"\bdocument\.(getElementById|querySelector(All)?|createElement|addEventListener|body)\b"#, Weight.decisive, cap: 2),
                // Browser and Node APIs: the clearest sign a script is meant
                // to run somewhere, which is exactly what the preview needs.
                marker(#"\b(HTMLElement|customElements|shadowRoot|attachShadow|localStorage|sessionStorage|navigator|IntersectionObserver|ResizeObserver|MutationObserver|matchMedia|getComputedStyle|innerHTML|textContent|classList|dataset|canvas|getContext)\b"#, Weight.decisive, cap: 2),
                marker(#"(?m)^#!.*\bnode\b"#, Weight.decisive),
                marker(#"(?m)^\s*(export\s+)?(async\s+)?function\s*\*?\s*\w+\s*\("#, Weight.strong, cap: 3),
                marker(#"\bfunction\s*\*?\s*\w*\s*\([\w\s,={}\[\].]*\)\s*\{|\bclass\s+\w+\s+extends\s+\w"#, Weight.medium, cap: 3),
                marker(#"(?m)^\s*export\s+(default|const|let|function|class|async|\{|\*)"#, Weight.strong, cap: 3),
                marker(#"(?m)^\s*import\s+[\w*{}, ]+\s+from\s+['"]"#, Weight.strong, cap: 3),
                marker(#"\bconsole\.(log|warn|error|info|debug|table)\s*\("#, Weight.strong, cap: 2),
                marker(#"\brequire\s*\(\s*['"]|\bJSON\.(parse|stringify)\b"#, Weight.strong, cap: 2),
                marker(#"\b(setTimeout|setInterval|requestAnimationFrame|fetch|addEventListener)\s*\("#, Weight.strong, cap: 3),
                marker(#"\bwindow\.\w|\bglobalThis\b|\bprocess\.env\b"#, Weight.strong, cap: 2),
                marker(#"\b(const|let)\s+[\w{\[$]"#, Weight.medium, cap: 4),
                marker(#"=>\s*[{(\w'"`\[]"#, Weight.medium, cap: 4),
                marker(#"\bawait\s+\w|\basync\s*\(|\bnew\s+Promise\b"#, Weight.medium, cap: 3),
                marker(#"\.(map|filter|reduce|forEach|then|catch)\s*\("#, Weight.medium, cap: 3),
                marker(#"\.\.\.\w|\$\{"#, Weight.medium, cap: 2)
            ]),

            Profile(language: .css, markers: [
                marker(#"(?m)^\s*@(media|keyframes|supports|font-face|layer|container|charset|tailwind|apply)\b"#, Weight.decisive, cap: 3),
                marker(#"(?m)^\s*--[\w-]+\s*:"#, Weight.decisive, cap: 3),
                marker(#"\bvar\(\s*--[\w-]+"#, Weight.decisive, cap: 3),
                marker(#"!important\b"#, Weight.decisive),
                marker(#"::(before|after|placeholder|selection|backdrop|first-line|marker)\b"#, Weight.decisive, cap: 2),
                marker(#":(hover|focus|active|disabled|checked|root|visited|nth-child|first-child|last-child|not|is|where)\b"#, Weight.strong, cap: 3),
                declarationMarker,
                marker(#"(?m)^\s*[.#]?[A-Za-z*][\w\-]*[^{};()=\n]*\{\s*$"#, Weight.medium, cap: 4),
                marker(#"\b(rgba?|hsla?|oklch|oklab|calc|translate[XYZ3d]*|scale|rotate|blur|cubic-bezier|linear-gradient|radial-gradient|conic-gradient)\s*\("#, Weight.medium, cap: 4),
                marker(#"[\s:]-?\d+(\.\d+)?(px|rem|em|vh|vw|fr|deg|ms)\b"#, Weight.weak, cap: 4)
            ], penalties: [
                // Style objects and template literals in JS look declarative;
                // real stylesheets never contain these.
                marker(#"(?m)^\s*(import|export|const|let|var|function|class|def|fn|func|package)\b"#, Weight.decisive, cap: 2),
                marker(#"=>|\bconsole\.|\breturn\b"#, Weight.decisive, cap: 2)
            ]),

            Profile(language: .html, markers: [
                marker(#"(?i)<!DOCTYPE\s+html"#, Weight.decisive),
                marker(#"(?i)</(script|style|template)\s*>"#, Weight.decisive, cap: 2),
                marker(#"(?i)<(html|head|body|main|section|header|footer|nav|article|aside|figure|dialog|canvas)\b"#, Weight.strong, cap: 4),
                marker(#"(?i)<(script|style|link|meta|title|base)\b"#, Weight.strong, cap: 4),
                marker(#"\sclass\s*=\s*["']"#, Weight.strong, cap: 4),
                marker(#"(?i)<(div|span|p|a|ul|ol|li|h[1-6]|img|button|input|form|table|tr|td|th|label|select|option|textarea|svg|path|circle|rect|g|use|pre|code|strong|em|br|hr)\b"#, Weight.medium, cap: 6),
                marker(#"(?i)</(div|span|p|a|body|html|head|section|h[1-6]|button|ul|ol|li|svg|main|header|footer|form|table|label|pre|code|figure|nav)\s*>"#, Weight.medium, cap: 6),
                marker(#"\s(href|src|alt|id|type|charset|lang|viewBox|xmlns|stroke|fill|width|height|placeholder|value|role|aria-\w+|data-[\w-]+)\s*=\s*["']"#, Weight.medium, cap: 6),
                marker(#"<!--|&(nbsp|amp|lt|gt|quot|#\d+);"#, Weight.medium, cap: 2)
            ])
        ]
    }

    // MARK: - Shared pieces

    /// A CSS declaration: a kebab/lowercase property, a value, a semicolon.
    /// The lookahead keeps TypeScript members (`start: number;`) out — those
    /// are the single most common false positive for a stylesheet.
    private static var declarationMarker: Marker? {
        marker(
            #"(?m)(?:^|[{;])\s*(-[a-z]+-)?[a-z][a-z-]{2,}\s*:\s*(?!\s*(string|number|boolean|any|void|unknown|never|null|undefined|symbol)\s*[;,)])[^;{}\n]+;"#,
            Weight.strong,
            cap: 6
        )
    }
}
