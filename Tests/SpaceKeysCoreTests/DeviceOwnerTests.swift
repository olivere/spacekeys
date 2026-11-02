import Testing
@testable import SpaceKeysCore

@Suite struct DeviceOwner {
    @Test func holderIsTheClientNotSeizedOut() {
        let clients = [
            HIDClient(pid: 1082, seizedOut: true),
            HIDClient(pid: 2714, seizedOut: true),
            HIDClient(pid: 7608, seizedOut: false),
        ]
        #expect(exclusiveOwner(of: clients, me: 1082) == 7608)
    }

    @Test func noOwnerWhileWeAreNotSeizedOut() {
        let clients = [HIDClient(pid: 1082, seizedOut: false), HIDClient(pid: 7608, seizedOut: false)]
        #expect(exclusiveOwner(of: clients, me: 1082) == nil)
    }

    @Test func noOwnerWhenWeAreNotAClient() {
        #expect(exclusiveOwner(of: [HIDClient(pid: 7608, seizedOut: false)], me: 1082) == nil)
    }

    @Test func seizedOutWithUnknownHolderHasNoOwner() {
        let clients = [HIDClient(pid: 1082, seizedOut: true), HIDClient(pid: 2714, seizedOut: true)]
        #expect(exclusiveOwner(of: clients, me: 1082) == nil)
    }

    @Test(arguments: [
        ("pid 7608, SpaceJuggler", Int32?.some(7608)),
        ("pid 439, WindowServer", 439),
        ("pid 12", 12),
        ("WindowServer", nil),
        ("pid x, y", nil),
    ])
    func pidFromCreator(creator: String, expected: Int32?) {
        #expect(HIDClient.pid(fromCreator: creator) == expected)
    }

    @Test func helperIsNamedAfterOutermostApp() {
        let path = "/Applications/Kugelblitz.app/Contents/Helpers/Space Juggler.app/Contents/MacOS/SpaceJuggler"
        #expect(displayName(forExecutablePath: path) == "Kugelblitz")
    }

    @Test func plainAppKeepsItsName() {
        #expect(displayName(forExecutablePath: "/Applications/Space Glider.app/Contents/MacOS/SpaceGlider") == "Space Glider")
    }

    @Test func toolOutsideABundleHasNoName() {
        #expect(displayName(forExecutablePath: "/usr/local/bin/spacebuttons") == nil)
    }
}
