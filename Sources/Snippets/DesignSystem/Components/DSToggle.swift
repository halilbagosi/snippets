import SwiftUI

public struct DSToggle: View {
    public var isOn: Binding<Bool>

    public init(isOn: Binding<Bool>) {
        self.isOn = isOn
    }

    public var body: some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(DSLiquidGlassToggleStyle())
    }
}

public struct DSLiquidGlassToggleStyle: ToggleStyle {
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Capsule()
                .fill(configuration.isOn ? DSToken.Color.textPrimary : DSToken.Color.surface)
                .frame(width: 50, height: 30)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .padding(2)
                        .offset(x: configuration.isOn ? 10 : -10)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isOn)
                )
                .onTapGesture {
                    withAnimation {
                        configuration.isOn.toggle()
                    }
                }
        }
    }
}
