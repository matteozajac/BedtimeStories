import Foundation
import MZAppFoundation
import MZAppFoundationLocal
import SwiftUI
import Testing
import UIKit
@testable import BedtimeStories

@Suite(.serialized) @MainActor
struct DeveloperConsoleTests {
    @Test func shakeAboveAlertPresentsConsoleAndPreservesAlert() async throws {
        let suite = "DeveloperConsoleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let options = DeveloperOptions(configuration: .init(bundleIdentifier: "com.example.diagnostics", urlScheme: "fixture", environment: .local), defaults: defaults)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: Text("Console fixture").appDeveloperTools(options))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await wait { Self.shakeResponder(in: window.rootViewController ?? host) != nil }
        let responder = try #require(Self.shakeResponder(in: window.rootViewController ?? host))
        let alert = UIAlertController(title: "Unfinished choice", message: "Preserve this alert", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep editing", style: .cancel))
        host.present(alert, animated: false)
        try await wait { alert.view.window != nil }
        // Exercise UIKit's shake callback in a live simulator scene. Hardware motion is separate.
        alert.motionEnded(.motionShake, with: nil)
        #expect(options.consoleRequested)
        try await wait { !window.isKeyWindow }
        #expect(host.presentedViewController === alert)
        options.setEnabled(false)
        try await wait { window.isKeyWindow }
        #expect(host.presentedViewController === alert)
        #expect(alert.title == "Unfinished choice")
        responder.motionEnded(.motionShake, with: nil)
        #expect(!options.consoleRequested && !options.isEnabled)
        #expect(!DeveloperOptions(configuration: .init(bundleIdentifier: "com.example.diagnostics", urlScheme: "fixture", environment: .local), defaults: defaults).isEnabled)
    }

    private static func shakeResponder(in controller: UIViewController) -> UIViewController? {
        if String(describing: type(of: controller)).contains("DeveloperResponderController"), controller.view.window != nil { return controller }
        return controller.children.lazy.compactMap { shakeResponder(in: $0) }.first
    }

    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(predicate())
    }
}
