/// A key on the SpaceMouse Pro (wired or wireless).
///
/// The raw value is the name used in the config file. `hidUsage` is the button
/// number in HID report 3, as the device's report descriptor declares it.
public enum DeviceButton: String, CaseIterable, Sendable {
    case menu, fit, top, right, front, roll
    case one = "1", two = "2", three = "3", four = "4"
    case esc, alt, shift, ctrl, lock

    public var hidUsage: Int {
        switch self {
        case .menu: 1
        case .fit: 2
        case .top: 3
        case .right: 5
        case .front: 6
        case .roll: 9
        case .one: 13
        case .two: 14
        case .three: 15
        case .four: 16
        case .esc: 23
        case .alt: 24
        case .shift: 25
        case .ctrl: 26
        case .lock: 27
        }
    }

    public init?(hidUsage: Int) {
        guard let button = DeviceButton.allCases.first(where: { $0.hidUsage == hidUsage }) else { return nil }
        self = button
    }
}
