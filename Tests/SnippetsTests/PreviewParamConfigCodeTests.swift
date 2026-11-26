import XCTest
@testable import Snippets

final class PreviewParamConfigCodeTests: XCTestCase {
    private let declared = [PreviewParam(name: "amplitude", kind: .number(default: 1.5))]

    private func variant(
        _ code: String, current: String, into configs: [PreviewParamConfig] = []
    ) -> (configs: [PreviewParamConfig], newID: UUID) {
        PreviewParamConfigStore.savingCodeVariant(
            code: code, values: [:], named: "Fast", sourceReviewID: nil,
            currentCode: current, declared: declared, into: configs
        )
    }

    func test_oldJSONDecodesWithNilCode() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Warm","values":{},"isDefault":false}
        """
        let config = try JSONDecoder().decode(PreviewParamConfig.self, from: Data(json.utf8))
        XCTAssertNil(config.code)
        XCTAssertNil(config.sourceReviewID)
    }

    func test_codeRoundTrips() throws {
        let id = UUID()
        let config = PreviewParamConfig(
            id: UUID(), name: "A", values: [:], isDefault: false, code: "x", sourceReviewID: id
        )
        let decoded = try JSONDecoder().decode(
            PreviewParamConfig.self, from: JSONEncoder().encode(config)
        )
        XCTAssertEqual(decoded, config)
    }

    func test_firstCodeVariantCapturesDefaultCode() {
        let result = variant("fast", current: "orig")
        XCTAssertEqual(result.configs.count, 2)
        XCTAssertTrue(result.configs[0].isDefault)
        XCTAssertEqual(result.configs[0].code, "orig")
        XCTAssertEqual(result.configs[0].values["amplitude"], .number(1.5))
        XCTAssertEqual(result.configs[1].id, result.newID)
        XCTAssertEqual(result.configs[1].code, "fast")
    }

    func test_secondCodeVariantDoesNotOverwriteDefaultCode() {
        let first = variant("fast", current: "orig")
        let second = variant("faster", current: "fast", into: first.configs)
        XCTAssertEqual(second.configs.count, 3)
        XCTAssertEqual(second.configs[0].code, "orig")
    }

    func test_variantFillsExistingValuesOnlyDefault() {
        let base = PreviewParamConfigStore.saving(
            current: [:], declared: declared, named: "Warm", into: []
        )
        XCTAssertNil(base[0].code)
        let result = variant("fast", current: "orig", into: base)
        XCTAssertEqual(result.configs[0].code, "orig")
        XCTAssertNil(result.configs[1].code)
    }

    func test_sourceReviewIDIsRecorded() {
        let reviewID = UUID()
        let result = PreviewParamConfigStore.savingCodeVariant(
            code: "c", values: [:], named: "N", sourceReviewID: reviewID,
            currentCode: "o", declared: declared, into: []
        )
        XCTAssertEqual(result.configs[1].sourceReviewID, reviewID)
    }

    func test_flushWritesOnlyToCodeConfigs() {
        let result = variant("fast", current: "orig")
        let codeID = result.newID
        let flushed = PreviewParamConfigStore.storingActiveCode(
            "edited", activeID: codeID, in: result.configs
        )
        XCTAssertEqual(flushed[1].code, "edited")
        XCTAssertEqual(flushed[0].code, "orig")

        let defaultFlushed = PreviewParamConfigStore.storingActiveCode(
            "orig2", activeID: result.configs[0].id, in: result.configs
        )
        XCTAssertEqual(defaultFlushed[0].code, "orig2")

        let valuesOnly = PreviewParamConfigStore.saving(
            current: [:], declared: declared, named: "Warm", into: []
        )
        let untouched = PreviewParamConfigStore.storingActiveCode(
            "x", activeID: valuesOnly[1].id, in: valuesOnly
        )
        XCTAssertEqual(untouched, valuesOnly)
        let defaultWithoutCode = PreviewParamConfigStore.storingActiveCode(
            "x", activeID: valuesOnly[0].id, in: valuesOnly
        )
        XCTAssertEqual(defaultWithoutCode, valuesOnly)
        XCTAssertEqual(
            PreviewParamConfigStore.storingActiveCode("x", activeID: nil, in: result.configs),
            result.configs
        )
    }

    func test_flushUnderValuesOnlyConfigWritesIntoDefaultOnceDefaultHasCode() {
        let valuesOnly = PreviewParamConfigStore.saving(
            current: [:], declared: declared, named: "V", into: []
        )
        let withCode = variant("fast", current: "orig", into: valuesOnly)
        let v = withCode.configs.first { $0.name == "V" }!
        let flushed = PreviewParamConfigStore.storingActiveCode(
            "edited", activeID: v.id, in: withCode.configs
        )
        XCTAssertEqual(flushed.first(where: \.isDefault)?.code, "edited")
        XCTAssertNil(flushed.first { $0.id == v.id }?.code)
        XCTAssertEqual(flushed.first { $0.id == withCode.newID }?.code, "fast")
    }

    func test_savingFromCodeConfigOwnsThatCode_andNeverWritesIntoDefault() {
        let reviewID = UUID()
        let opt = PreviewParamConfigStore.savingCodeVariant(
            code: "opt", values: [:], named: "Opt", sourceReviewID: reviewID,
            currentCode: "orig", declared: declared, into: []
        )
        // The user edits under Opt, moves a slider, saves "V".
        let saved = PreviewParamConfigStore.saving(
            current: [:], declared: declared, named: "V",
            snippetCode: "opt edited", activeID: opt.newID, into: opt.configs
        )
        let v = saved.last!
        XCTAssertEqual(v.code, "opt edited")
        XCTAssertEqual(v.sourceReviewID, reviewID)
        XCTAssertEqual(saved.first { $0.id == opt.newID }?.code, "opt edited")
        XCTAssertEqual(saved.first(where: \.isDefault)?.code, "orig")

        // Later flushes while V is active stay in V.
        let later = PreviewParamConfigStore.storingActiveCode("more", activeID: v.id, in: saved)
        XCTAssertEqual(later.first(where: \.isDefault)?.code, "orig")
        XCTAssertEqual(later.last?.code, "more")
    }

    func test_savingFromDefaultOrValuesOnlyDoesNotInventCode() {
        let base = PreviewParamConfigStore.saving(
            current: [:], declared: declared, named: "A", into: []
        )
        let next = PreviewParamConfigStore.saving(
            current: [:], declared: declared, named: "B",
            snippetCode: "x", activeID: base[1].id, into: base
        )
        XCTAssertNil(next.last?.code)
        XCTAssertNil(next.last?.sourceReviewID)
        XCTAssertEqual(next, base + [next.last!])
    }

    func test_codeToActivateForValuesOnlyConfig() {
        let valuesOnly = PreviewParamConfigStore.saving(
            current: [:], declared: declared, named: "Warm", into: []
        )
        XCTAssertNil(PreviewParamConfigStore.codeToActivate(for: valuesOnly[1].id, in: valuesOnly))

        let withCode = variant("fast", current: "orig", into: valuesOnly)
        XCTAssertEqual(
            PreviewParamConfigStore.codeToActivate(for: valuesOnly[1].id, in: withCode.configs), "orig"
        )
        XCTAssertEqual(
            PreviewParamConfigStore.codeToActivate(for: withCode.newID, in: withCode.configs), "fast"
        )
        XCTAssertNil(PreviewParamConfigStore.codeToActivate(for: UUID(), in: withCode.configs))
    }

    func test_deletingDefaultIsRefused() {
        let result = variant("fast", current: "orig")
        let after = PreviewParamConfigStore.deleting(id: result.configs[0].id, from: result.configs)
        XCTAssertEqual(after, result.configs)
        let afterCodeDelete = PreviewParamConfigStore.deleting(id: result.newID, from: result.configs)
        XCTAssertEqual(afterCodeDelete.count, 1)
    }
}
