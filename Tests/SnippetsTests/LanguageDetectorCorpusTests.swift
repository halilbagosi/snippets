import XCTest
@testable import Snippets

/// Realistic, whole-file samples of the kind users actually paste, one per
/// language family. Every case here asserts the language that makes the
/// *preview* render correctly, which is the only reason detection exists.
final class LanguageDetectorCorpusTests: XCTestCase {

    // MARK: React / JSX

    func test_jsxComponentWithoutReactImport_detectsReact() {
        let code = """
        export default function Card({ title, body }) {
          return (
            <div className="card">
              <h2 className="card-title">{title}</h2>
              <p>{body}</p>
            </div>
          );
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .react)
    }

    func test_tsxComponentWithTypeAnnotations_detectsReact() {
        let code = """
        import { useState } from 'react';

        interface CounterProps {
          start: number;
          label: string;
        }

        export const Counter = ({ start, label }: CounterProps) => {
          const [count, setCount] = useState<number>(start);
          return (
            <button onClick={() => setCount(count + 1)}>
              {label}: {count}
            </button>
          );
        };
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .react)
    }

    func test_reactComponentUsingHooksOnly_detectsReact() {
        let code = """
        function useInterval(callback, delay) {
          const savedCallback = useRef(callback);

          useEffect(() => {
            savedCallback.current = callback;
          }, [callback]);

          useEffect(() => {
            const id = setInterval(() => savedCallback.current(), delay);
            return () => clearInterval(id);
          }, [delay]);
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .react)
    }

    // MARK: HTML

    func test_htmlDocumentWithInlineScript_staysHTML() {
        let code = """
        <!DOCTYPE html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <title>Demo</title>
          </head>
          <body>
            <div id="app"></div>
            <script>
              const root = document.getElementById('app');
              const render = () => {
                console.log('rendering');
                root.textContent = 'hello';
              };
              render();
            </script>
          </body>
        </html>
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .html)
    }

    func test_htmlFragmentWithInlineStyleBlock_staysHTML() {
        let code = """
        <section class="hero">
          <style>
            .hero { display: flex; padding: 24px; background: #111; }
            .hero h1 { font-size: 48px; color: white; }
          </style>
          <h1>Ship it</h1>
        </section>
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .html)
    }

    func test_svgMarkup_detectsHTML() {
        let code = """
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" />
          <path d="M8 12l3 3 5-6" stroke="currentColor" stroke-width="2" />
        </svg>
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .html)
    }

    // MARK: CSS

    func test_modernCSSWithCustomProperties_detectsCSS() {
        let code = """
        :root {
          --accent: oklch(70% 0.2 250);
          --radius: 12px;
        }

        .panel {
          border-radius: var(--radius);
          backdrop-filter: blur(20px);
          transition: transform 240ms cubic-bezier(0.2, 0, 0, 1);
        }

        @media (prefers-color-scheme: dark) {
          .panel { background: rgb(0 0 0 / 0.4); }
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .css)
    }

    func test_keyframesOnlyStylesheet_detectsCSS() {
        let code = """
        @keyframes shimmer {
          from { transform: translateX(-100%); }
          to { transform: translateX(100%); }
        }

        .skeleton::after {
          animation: shimmer 1.4s infinite;
          content: "";
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .css)
    }

    func test_cssInJSStyleObject_detectsJavaScriptNotCSS() {
        let code = """
        export const styles = {
          container: {
            display: 'flex',
            padding: 16,
            background: '#111',
            color: 'white',
          },
        };
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .javascript)
    }

    // MARK: JavaScript / TypeScript

    func test_vanillaJSModule_detectsJavaScript() {
        let code = """
        const items = [1, 2, 3];

        export function total(list) {
          return list.reduce((sum, n) => sum + n, 0);
        }

        document.addEventListener('DOMContentLoaded', () => {
          console.log(total(items));
        });
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .javascript)
    }

    func test_typescriptInterfacesAndGenerics_detectsTypeScript() {
        let code = """
        export interface Repository<T> {
          find(id: string): Promise<T | undefined>;
          save(entity: T): Promise<void>;
        }

        export type Result<T> = { ok: true; value: T } | { ok: false; error: Error };

        export async function loadAll<T>(repo: Repository<T>, ids: string[]): Promise<T[]> {
          const found: T[] = [];
          for (const id of ids) {
            const item = await repo.find(id);
            if (item !== undefined) found.push(item);
          }
          return found;
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .typescript)
    }

    // MARK: JSON

    func test_prettyPrintedJSON_detectsJSON() {
        let code = """
        {
          "name": "snippets",
          "version": "1.2.0",
          "dependencies": { "ogl": "^1.0.0" },
          "keywords": ["swift", "macos"]
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .json)
    }

    func test_largeValidJSON_detectsJSON() {
        let entries = (0..<200).map { #"{"id": \#($0), "name": "row \#($0)"}"# }
        let code = "[\n" + entries.joined(separator: ",\n") + "\n]"
        XCTAssertGreaterThan(code.utf8.count, 2_048)
        XCTAssertEqual(LanguageDetector.detect(code: code), .json)
    }

    func test_largeBraceLeadingJavaScriptObject_isNotJSON() {
        // Starts with `{` and exceeds the scan window, but it is executable JS.
        let filler = (0..<120)
            .map { "  handler\($0): () => console.log('event \($0)')," }
            .joined(separator: "\n")
        let code = "{\n" + filler + "\n  teardown() { window.removeEventListener('x', this.h); },\n}"
        XCTAssertGreaterThan(code.utf8.count, 2_048)
        XCTAssertEqual(LanguageDetector.detect(code: code), .javascript)
    }

    // MARK: Shaders

    func test_metalFragmentShader_detectsMetal() {
        let code = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        fragment float4 gradient(VertexOut in [[stage_in]],
                                 constant float &time [[buffer(0)]]) {
            float3 c = float3(in.uv, 0.5 + 0.5 * sin(time));
            return float4(c, 1.0);
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .metal)
    }

    func test_metalComputeKernel_detectsMetal() {
        let code = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void blur(texture2d<float, access::read> src [[texture(0)]],
                         texture2d<float, access::write> dst [[texture(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
            float4 sum = src.read(gid);
            dst.write(sum, gid);
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .metal)
    }

    func test_hlslPixelShader_detectsHLSL() {
        let code = """
        cbuffer Constants : register(b0) {
            float4x4 viewProjection;
            float time;
        };

        Texture2D albedo : register(t0);
        SamplerState linearSampler : register(s0);

        struct PSInput {
            float4 position : SV_POSITION;
            float2 uv : TEXCOORD0;
        };

        float4 main(PSInput input) : SV_TARGET {
            return albedo.Sample(linearSampler, input.uv) * time;
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .hlsl)
    }

    func test_glslWithoutVersionDirective_detectsGLSL() {
        let code = """
        precision mediump float;

        varying vec2 vUv;
        uniform float uTime;

        void main() {
            vec3 color = 0.5 + 0.5 * cos(uTime + vUv.xyx + vec3(0.0, 2.0, 4.0));
            gl_FragColor = vec4(color, 1.0);
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .glsl)
    }

    func test_shadertoyStyleGLSL_detectsGLSL() {
        let code = """
        void mainImage(out vec4 fragColor, in vec2 fragCoord) {
            vec2 uv = fragCoord / iResolution.xy;
            float d = length(uv - 0.5);
            vec3 col = mix(vec3(0.1), vec3(0.9, 0.3, 0.6), smoothstep(0.4, 0.0, d));
            fragColor = vec4(col, 1.0);
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .glsl)
    }

    // MARK: Swift

    func test_swiftUIView_detectsSwift() {
        let code = """
        import SwiftUI

        struct ProfileCard: View {
            @State private var isExpanded = false
            let name: String

            var body: some View {
                VStack(alignment: .leading, spacing: 8) {
                    Text(name).font(.headline)
                    if isExpanded {
                        Text("More detail").foregroundStyle(.secondary)
                    }
                }
                .onTapGesture { isExpanded.toggle() }
            }
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .swift)
    }

    func test_plainSwiftModelWithoutSwiftUI_detectsSwift() {
        let code = """
        import Foundation

        final class Debouncer {
            private var workItem: DispatchWorkItem?
            private let interval: TimeInterval

            init(interval: TimeInterval) {
                self.interval = interval
            }

            func call(_ action: @escaping () -> Void) {
                workItem?.cancel()
                let item = DispatchWorkItem(block: action)
                workItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: item)
            }
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .swift)
    }

    // MARK: Other backends (must not be mistaken for previewable languages)

    func test_pythonScriptWithTypeHints_detectsPython() {
        let code = """
        from dataclasses import dataclass

        @dataclass
        class Point:
            x: float
            y: float

            def distance(self, other: "Point") -> float:
                return ((self.x - other.x) ** 2 + (self.y - other.y) ** 2) ** 0.5

        if __name__ == "__main__":
            print(Point(0, 0).distance(Point(3, 4)))
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .python)
    }

    func test_pythonShebangScript_detectsPython() {
        let code = """
        #!/usr/bin/env python3
        import sys

        for line in sys.stdin:
            sys.stdout.write(line.upper())
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .python)
    }

    func test_goHTTPServer_detectsGo() {
        let code = """
        package main

        import (
            "fmt"
            "net/http"
        )

        func handler(w http.ResponseWriter, r *http.Request) {
            fmt.Fprintf(w, "hello %s", r.URL.Path)
        }

        func main() {
            http.HandleFunc("/", handler)
            if err := http.ListenAndServe(":8080", nil); err != nil {
                panic(err)
            }
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .go)
    }

    func test_rustStructWithImpl_detectsRust() {
        let code = """
        use std::collections::HashMap;

        #[derive(Debug, Clone)]
        pub struct Counter {
            counts: HashMap<String, usize>,
        }

        impl Counter {
            pub fn new() -> Self {
                Self { counts: HashMap::new() }
            }

            pub fn bump(&mut self, key: &str) {
                let entry = self.counts.entry(key.to_string()).or_insert(0);
                *entry += 1;
            }
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .rust)
    }

    func test_kotlinDataClassAndCoroutine_detectsKotlin() {
        let code = """
        package com.example.app

        import kotlinx.coroutines.delay

        data class User(val id: Long, val name: String)

        class UserRepository {
            private val cache = mutableMapOf<Long, User>()

            suspend fun load(id: Long): User? {
                delay(100)
                return cache[id]
            }

            companion object {
                const val TAG = "UserRepository"
            }
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .kotlin)
    }

    func test_cppClassWithTemplates_detectsCpp() {
        let code = """
        #include <vector>
        #include <iostream>

        template <typename T>
        class Stack {
        public:
            void push(const T& value) { data_.push_back(value); }
            T pop() {
                T value = data_.back();
                data_.pop_back();
                return value;
            }
        private:
            std::vector<T> data_;
        };

        int main() {
            Stack<int> s;
            s.push(42);
            std::cout << s.pop() << std::endl;
            return 0;
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .cpp)
    }

    // MARK: Non-code and edge cases

    func test_emptyString_isUnknown() {
        XCTAssertEqual(LanguageDetector.detect(code: ""), .unknown)
        XCTAssertEqual(LanguageDetector.detect(code: "   \n\n  \t "), .unknown)
    }

    func test_plainProse_isUnknown() {
        let code = """
        Remember to ask the design team about the hover state before
        shipping the new panel. The current spacing is fine but the
        motion feels a little slow on large displays.
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .unknown)
    }

    func test_markdownFencedSnippet_detectsFencedLanguage() {
        let code = """
        ```css
        .btn { display: inline-flex; padding: 8px 16px; border-radius: 8px; }
        ```
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .css)
    }

    func test_commentedOutOtherLanguageDoesNotWin() {
        // A JS file whose comments quote Swift; comments must not outvote code.
        let code = """
        // Ported from Swift:
        //   struct Debouncer { func call(_ action: @escaping () -> Void) { } }
        //   guard let item = workItem else { return }
        //   var body: some View { Text("hi") }
        export function debounce(fn, wait) {
          let timer;
          return (...args) => {
            clearTimeout(timer);
            timer = setTimeout(() => fn(...args), wait);
          };
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .javascript)
    }

    func test_stringContentsDoNotDecideLanguage() {
        // The long string body is prose about Python; the code is JS.
        let code = """
        const helpText = "def main(): import os; print(self.value) if __name__ else None";
        export const show = () => console.log(helpText);
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .javascript)
    }

    func test_htmlDocumentBeyondScanWindow_stillDetectsHTML() {
        // Signal-free filler ahead of the markup: detection must not depend on
        // everything interesting living in the first two kilobytes.
        let filler = String(repeating: "<!-- spacer comment line -->\n", count: 200)
        let code = filler + """
        <div class="wrapper">
          <p>Actual content down here.</p>
        </div>
        """
        XCTAssertGreaterThan(code.utf8.count, 2_048)
        XCTAssertEqual(LanguageDetector.detect(code: code), .html)
    }

    // MARK: Determinism / performance guard

    func test_detectionIsStableAcrossRepeatedCalls() {
        let code = "const x = 1;\nexport default () => console.log(x);"
        let first = LanguageDetector.detect(code: code)
        for _ in 0..<50 {
            XCTAssertEqual(LanguageDetector.detect(code: code), first)
        }
    }

    func test_typicalSnippetDetectsWithinAFrame() {
        // The editor re-detects on every keystroke, so this is the budget
        // that matters. A ~1 KB snippet is the common case.
        let code = String(repeating: "const value = compute(1, 2, 3);\n", count: 40)
        _ = LanguageDetector.detect(code: code)  // warm the compiled markers
        let start = Date()
        for _ in 0..<20 { _ = LanguageDetector.detect(code: code) }
        XCTAssertLessThan(Date().timeIntervalSince(start) / 20, 0.005)
    }

    func test_veryLargeInputStaysBounded() {
        // Cost is capped by the scan window, not by file size.
        let code = String(repeating: "const value = compute(1, 2, 3);\n", count: 4_000)
        let start = Date()
        _ = LanguageDetector.detect(code: code)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.05)
    }
}

