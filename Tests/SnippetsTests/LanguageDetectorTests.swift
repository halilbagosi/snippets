import XCTest
@testable import Snippets

final class LanguageDetectorTests: XCTestCase {
    func test_reactComponentWithEmbeddedGLSLTemplateLiterals_detectsReact() {
        let code = """
        import { useRef, useEffect } from 'react';
        import { Renderer, Program, Mesh, Triangle, Color } from 'ogl';

        const FRAG = `#version 300 es
        precision highp float;
        uniform vec2 uCenter;
        uniform float uRadius;
        out vec4 fragColor;
        void main() {
          fragColor = vec4(1.0);
        }
        `;

        const SpecularButton = ({ children }) => {
          const btnRef = useRef(null);
          useEffect(() => {}, []);
          return <button ref={btnRef}>{children}</button>;
        };

        export default SpecularButton;
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .react)
    }

    func test_plainGLSLFragmentShader_detectsGLSL() {
        let code = """
        #version 300 es
        precision highp float;
        uniform vec2 uResolution;
        out vec4 fragColor;
        void main() {
          fragColor = vec4(gl_FragCoord.xy / uResolution, 0.0, 1.0);
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .glsl)
    }

    func test_swiftWithEmbeddedShaderInMultilineString_detectsSwift() {
        let code = """
        import SwiftUI

        struct ShaderButton: View {
            let source = \"\"\"
            uniform float uTime;
            varying vec2 vUV;
            void main() { gl_FragColor = vec4(vUV, 0.0, 1.0); }
            \"\"\"

            var body: some View {
                Text("Hello")
            }
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .swift)
    }

    func test_javascriptWithEmbeddedShaderTemplateLiteral_doesNotDetectGLSL() {
        let code = """
        const vert = `
        uniform mat4 uProjection;
        varying vec2 vUV;
        void main() { gl_Position = uProjection * vec4(0.0); }
        `;
        const draw = () => console.log(vert);
        function render() { console.log('frame'); }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .javascript)
    }

    // MARK: JSX usage snippets (bare component tags, no react markers)

    func test_jsxUsageWithClosingTags_detectsReactNotHTML() {
        let code = """
        import Strands from './Strands';

        <Strands colorStops={["#ff94b8"]} amplitude={1}></Strands>
        <Strands colorStops={["#ffd36e"]} amplitude={1.4}></Strands>
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .react)
    }

    func test_jsxUsageSelfClosing_detectsReactNotUnknown() {
        let code = """
        import Strands from './Strands';

        <Strands colorStops={["#ff94b8"]} amplitude={1} />
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .react)
    }

    func test_plainLowercaseHTML_staysHTML() {
        XCTAssertEqual(
            LanguageDetector.detect(code: "<div class=\"x\"><p>hi</p></div>"), .html
        )
    }

    func test_legacyUppercaseHTML_staysHTML() {
        XCTAssertEqual(
            LanguageDetector.detect(code: "<HTML><BODY><P>hi</P></BODY></HTML>"), .html
        )
    }

    func test_genericTypeAnnotations_doNotTriggerJSXTieBreak() {
        // No confident language hits, but `Array<String>` must not read as a tag.
        XCTAssertNotEqual(
            LanguageDetector.detect(code: "let items: Array<String> = makeItems()"), .react
        )
    }
}
