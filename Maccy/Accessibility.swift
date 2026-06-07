import AppKit

struct Accessibility {
  static var isTrusted: Bool { AXIsProcessTrustedWithOptions(nil) }

  static func check() {
    guard !isTrusted else {
      return
    }
  }
}

protocol AccessibilityTrustChecking {
  var isTrusted: Bool { get }
}

struct SystemAccessibilityTrustChecker: AccessibilityTrustChecking {
  var isTrusted: Bool { Accessibility.isTrusted }
}
