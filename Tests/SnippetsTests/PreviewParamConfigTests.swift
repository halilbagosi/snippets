import XCTest
@testable import Snippets

final class PreviewParamConfigTests: XCTestCase {
    private let declared = [
        PreviewParam(name: "amplitude", kind: .number(default: 1.5)),
        PreviewParam(name: "tint", kind: .color(defaultHex: "#ff0000"))
    ]

    func test_firstSaveAlsoCreatesDefaultHoldingDeclaredValues() {
        let configs = PreviewParamConfigStore.saving(
            current: ["amplitude": .number(4)], declared: declared, named: "Warm", into: []
        )
        XCTAssertEqual(configs.count, 2)
        XCTAssertTrue(configs[0].isDefault)
        XCTAssertEqual(configs[0].name, "Default")
        XCTAssertEqual(configs[0].values["amplitude"], .number(1.5))
        XCTAssertEqual(configs[0].values["tint"], .string("#ff0000"))
        XCTAssertEqual(configs[1].name, "Warm")
        XCTAssertEqual(configs[1].values["amplitude"], .number(4))
    }

    func test_savedConfigCapturesEveryDeclaredParamNotJustChangedOnes() {
        let configs = PreviewParamConfigStore.saving(
            current: ["amplitude": .number(4)], declared: declared, named: "Warm", into: []
        )
        XCTAssertEqual(configs[1].values["tint"], .string("#ff0000"))
    }

    func test_secondSaveDoesNotCreateAnotherDefault() {
        let first = PreviewParamConfigStore.saving(
            current: ["amplitude": .number(4)], declared: declared, named: "Warm", into: []
        )
        let second = PreviewParamConfigStore.saving(
            current: ["amplitude": .number(9)], declared: declared, named: "Cool", into: first
        )
        XCTAssertEqual(second.count, 3)
        XCTAssertEqual(second.filter(\.isDefault).count, 1)
        XCTAssertEqual(second[0].values["amplitude"], .number(1.5), "Default must stay frozen")
    }

    func test_updatingRewritesNamedConfigOnly() {
        let configs = PreviewParamConfigStore.saving(
            current: ["amplitude": .number(4)], declared: declared, named: "Warm", into: []
        )
        let updated = PreviewParamConfigStore.updating(
            id: configs[1].id, to: ["amplitude": .number(7)], declared: declared, in: configs
        )
        XCTAssertEqual(updated[1].values["amplitude"], .number(7))
        XCTAssertEqual(updated[0].values["amplitude"], .number(1.5))
    }

    func test_updatingDefaultIsRefused() {
        let configs = PreviewParamConfigStore.saving(
            current: ["amplitude": .number(4)], declared: declared, named: "Warm", into: []
        )
        let updated = PreviewParamConfigStore.updating(
            id: configs[0].id, to: ["amplitude": .number(99)], declared: declared, in: configs
        )
        XCTAssertEqual(updated, configs, "Default is immutable")
    }

    func test_deletingDefaultIsRefused() {
        let configs = PreviewParamConfigStore.saving(
            current: ["amplitude": .number(4)], declared: declared, named: "Warm", into: []
        )
        XCTAssertEqual(PreviewParamConfigStore.deleting(id: configs[0].id, from: configs), configs)
        XCTAssertEqual(PreviewParamConfigStore.deleting(id: configs[1].id, from: configs).count, 1)
    }

    func test_resolvedValuesSkipsParamsTheCodeNoLongerDeclares() {
        let config = PreviewParamConfig(
            id: UUID(), name: "Stale",
            values: ["amplitude": .number(4), "gone": .number(1)], isDefault: false
        )
        let resolved = PreviewParamConfigStore.resolvedValues(for: config, declared: declared)
        XCTAssertEqual(resolved["amplitude"], .number(4))
        XCTAssertNil(resolved["gone"])
    }

    func test_configRoundTripsThroughJSON() throws {
        let config = PreviewParamConfig(
            id: UUID(), name: "Warm",
            values: ["amplitude": .number(4), "on": .boolean(true), "tint": .string("#abc")],
            isDefault: false
        )
        let data = try JSONEncoder().encode([config])
        let decoded = try JSONDecoder().decode([PreviewParamConfig].self, from: data)
        XCTAssertEqual(decoded, [config])
    }
}
