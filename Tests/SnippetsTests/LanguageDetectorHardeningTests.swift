import XCTest
@testable import Snippets

/// Adversarial cases: sources that deliberately look like the wrong language,
/// and unsupported languages that must land on `.unknown` rather than being
/// handed to a preview engine that cannot render them.
final class LanguageDetectorHardeningTests: XCTestCase {

    // MARK: Unsupported languages must not claim a preview engine

    func test_sqlQuery_isNotPreviewable() {
        let code = """
        SELECT u.id, u.name, COUNT(o.id) AS order_count
        FROM users u
        JOIN orders o ON o.user_id = u.id
        WHERE u.created_at > '2024-01-01'
        GROUP BY u.id, u.name
        ORDER BY order_count DESC
        LIMIT 50;
        """
        XCTAssertNil(LanguageDetector.detect(code: code).previewKind)
    }

    func test_yamlConfig_isNotPreviewable() {
        let code = """
        version: 2.1

        jobs:
          build:
            docker:
              - image: cimg/node:20.11
            steps:
              - checkout
              - run:
                  name: Install dependencies
                  command: npm ci
        """
        XCTAssertNil(LanguageDetector.detect(code: code).previewKind)
    }

    func test_shellScript_isNotPreviewable() {
        let code = """
        #!/usr/bin/env bash
        set -euo pipefail

        for file in "$@"; do
          if [[ -f "$file" ]]; then
            echo "processing $file"
          fi
        done
        """
        XCTAssertNil(LanguageDetector.detect(code: code).previewKind)
    }

    func test_tomlConfig_isNotPreviewable() {
        let code = """
        [package]
        name = "example"
        version = "0.1.0"

        [dependencies]
        serde = { version = "1.0", features = ["derive"] }
        """
        XCTAssertNil(LanguageDetector.detect(code: code).previewKind)
    }

    // MARK: Markup that borrows JSX-looking syntax

    func test_alpineAndHtmxAttributes_stayHTML() {
        let code = """
        <div x-data="{ open: false }" class="dropdown">
          <button @click="open = !open" class="trigger">Menu</button>
          <ul x-show="open" hx-get="/items" hx-target="#list" class="menu">
            <li>First</li>
            <li>Second</li>
          </ul>
        </div>
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .html)
    }

    func test_tailwindUtilityMarkup_staysHTML() {
        let code = """
        <div class="flex min-h-screen items-center justify-center bg-slate-900">
          <article class="rounded-2xl bg-white/5 p-8 shadow-xl backdrop-blur">
            <h1 class="text-2xl font-semibold text-white">Pricing</h1>
            <p class="mt-2 text-sm text-slate-400">Simple, transparent.</p>
          </article>
        </div>
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .html)
    }

    // MARK: JS that borrows CSS-looking syntax

    func test_styledComponentsTemplate_isNotCSS() {
        let code = """
        import styled from 'styled-components';

        const Button = styled.button`
          padding: 12px 24px;
          border-radius: 8px;
          background: ${props => props.color};
        `;

        export default Button;
        """
        XCTAssertNotEqual(LanguageDetector.detect(code: code), .css)
    }

    func test_webComponentUsingDOMAPIs_detectsJavaScript() {
        let code = """
        class Counter extends HTMLElement {
          connectedCallback() {
            this.attachShadow({ mode: 'open' });
            this.shadowRoot.innerHTML = '<button>+</button>';
            this.shadowRoot.querySelector('button').onclick = () => this.bump();
          }

          bump() {
            this.count = (this.count || 0) + 1;
          }
        }

        customElements.define('x-counter', Counter);
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .javascript)
    }

    func test_minifiedJavaScriptOneLiner_detectsJavaScript() {
        let code = "const t=(e,n)=>e*n;function r(e){return t(e,2)}export default{r,t};"
        XCTAssertEqual(LanguageDetector.detect(code: code), .javascript)
    }

    // MARK: Comments and configuration dialects

    func test_jsonWithCommentsAndTrailingCommas_detectsJSON() {
        let code = """
        {
          // Editor preferences
          "editor.fontSize": 13,
          "editor.tabSize": 2, // two spaces
          "files.exclude": {
            "**/.git": true,
          },
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .json)
    }

    func test_pythonWithCommentQuotingJavaScript_detectsPython() {
        let code = """
        # Mirrors the JS helper:
        #   const total = items.reduce((sum, n) => sum + n, 0);
        #   console.log(total);
        def total(items):
            return sum(items)

        if __name__ == "__main__":
            print(total([1, 2, 3]))
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .python)
    }

    func test_typescriptDeclarationFile_detectsTypeScript() {
        let code = """
        declare module 'ogl' {
          export class Renderer {
            constructor(options?: { alpha?: boolean; dpr?: number });
            render(scene: unknown): void;
          }
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .typescript)
    }

    // MARK: Shader dialects that share a base language

    func test_glslVertexShaderWithAttributes_detectsGLSL() {
        let code = """
        attribute vec3 position;
        attribute vec2 uv;

        uniform mat4 modelViewMatrix;
        uniform mat4 projectionMatrix;

        varying vec2 vUv;

        void main() {
            vUv = uv;
            gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .glsl)
    }

    func test_metalVertexShaderWithCppIdioms_detectsMetal() {
        let code = """
        #include <metal_stdlib>
        #include <simd/simd.h>
        using namespace metal;

        struct Vertex {
            float2 position;
            float2 uv;
        };

        vertex VertexOut passthrough(const device Vertex *vertices [[buffer(0)]],
                                     uint vid [[vertex_id]]) {
            VertexOut out;
            out.position = float4(vertices[vid].position, 0.0, 1.0);
            return out;
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .metal)
    }

    // MARK: Editor behaviour — detection runs on every keystroke

    func test_partiallyTypedReactComponent_settlesOnReact() {
        // A component mid-typing: unbalanced braces, an unclosed tag.
        let code = """
        import { useState } from 'react';

        export default function Toggle() {
          const [on, setOn] = useState(false);
          return (
            <button onClick={() => setOn(!on
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .react)
    }

    func test_unterminatedStringDoesNotSwallowTheFile() {
        // The stray quote must not blank the markup that follows it.
        let code = """
        <section class="hero">
          <p>It's a test of don't-break-here handling</p>
          <a href="/next">Continue</a>
        </section>
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .html)
    }
}
