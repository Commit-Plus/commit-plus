// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import Foundation

@MainActor
final class DiffAppearanceSettingsStore: ObservableObject {
    static let shared = DiffAppearanceSettingsStore()

    static let defaultFontName = "Menlo-Regular"
    static let defaultFontSize = 12.0

    @Published var fontName: String {
        didSet {
            userDefaults.set(fontName, forKey: Keys.fontName)
            revision += 1
        }
    }

    @Published var fontSize: Double {
        didSet {
            userDefaults.set(fontSize, forKey: Keys.fontSize)
            revision += 1
        }
    }

    @Published var addedBackgroundColor: NSColor {
        didSet {
            save(addedBackgroundColor, forKey: Keys.addedBackgroundColor)
            revision += 1
        }
    }

    @Published var addedTextColor: NSColor {
        didSet {
            save(addedTextColor, forKey: Keys.addedTextColor)
            revision += 1
        }
    }

    @Published var removedBackgroundColor: NSColor {
        didSet {
            save(removedBackgroundColor, forKey: Keys.removedBackgroundColor)
            revision += 1
        }
    }

    @Published var removedTextColor: NSColor {
        didSet {
            save(removedTextColor, forKey: Keys.removedTextColor)
            revision += 1
        }
    }

    @Published private(set) var revision = 0

    var font: NSFont {
        NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var draft: DiffAppearanceSettingsDraft {
        DiffAppearanceSettingsDraft(
            fontName: fontName,
            fontSize: fontSize,
            addedBackgroundColor: addedBackgroundColor,
            addedTextColor: addedTextColor,
            removedBackgroundColor: removedBackgroundColor,
            removedTextColor: removedTextColor
        )
    }

    var snapshotValues: (
        fontName: String,
        fontSize: Double,
        addedBackgroundColor: String,
        addedTextColor: String,
        removedBackgroundColor: String,
        removedTextColor: String
    ) {
        (
            fontName,
            fontSize,
            Self.hexString(from: addedBackgroundColor),
            Self.hexString(from: addedTextColor),
            Self.hexString(from: removedBackgroundColor),
            Self.hexString(from: removedTextColor)
        )
    }

    private enum Keys {
        static let fontName = "diff.appearance.fontName"
        static let fontSize = "diff.appearance.fontSize"
        static let addedBackgroundColor = "diff.appearance.addedBackgroundColor"
        static let addedTextColor = "diff.appearance.addedTextColor"
        static let removedBackgroundColor = "diff.appearance.removedBackgroundColor"
        static let removedTextColor = "diff.appearance.removedTextColor"
    }

    private enum Defaults {
        static let addedBackgroundColor = NSColor(
            srgbRed: 0.00, green: 0.65, blue: 0.40, alpha: 0.12
        )
        static let addedTextColor = NSColor(
            srgbRed: 0.00, green: 0.43, blue: 0.31, alpha: 1
        )
        static let removedBackgroundColor = NSColor(
            srgbRed: 0.90, green: 0.20, blue: 0.12, alpha: 0.12
        )
        static let removedTextColor = NSColor(
            srgbRed: 0.78, green: 0.18, blue: 0.05, alpha: 1
        )
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        fontName = userDefaults.string(forKey: Keys.fontName) ?? Self.defaultFontName
        let storedFontSize = userDefaults.object(forKey: Keys.fontSize) as? Double
        fontSize = storedFontSize.map { min(max($0, 8), 32) } ?? Self.defaultFontSize
        addedBackgroundColor = Self.color(
            storedIn: userDefaults, key: Keys.addedBackgroundColor,
            fallback: Defaults.addedBackgroundColor
        )
        addedTextColor = Self.color(
            storedIn: userDefaults, key: Keys.addedTextColor,
            fallback: Defaults.addedTextColor
        )
        removedBackgroundColor = Self.color(
            storedIn: userDefaults, key: Keys.removedBackgroundColor,
            fallback: Defaults.removedBackgroundColor
        )
        removedTextColor = Self.color(
            storedIn: userDefaults, key: Keys.removedTextColor,
            fallback: Defaults.removedTextColor
        )
        addedBackgroundColor = Self.updatedBackground(addedBackgroundColor, added: true)
        removedBackgroundColor = Self.updatedBackground(removedBackgroundColor, added: false)
    }

    func restoreDefaults() {
        apply(Self.defaultDraft)
    }

    func apply(_ draft: DiffAppearanceSettingsDraft) {
        fontName = draft.fontName
        fontSize = min(max(draft.fontSize, 8), 32)
        addedBackgroundColor = Self.updatedBackground(draft.addedBackgroundColor, added: true).usingColorSpace(.sRGB)
            ?? Defaults.addedBackgroundColor
        addedTextColor = draft.addedTextColor.usingColorSpace(.sRGB)
            ?? Defaults.addedTextColor
        removedBackgroundColor = Self.updatedBackground(draft.removedBackgroundColor, added: false).usingColorSpace(.sRGB)
            ?? Defaults.removedBackgroundColor
        removedTextColor = draft.removedTextColor.usingColorSpace(.sRGB)
            ?? Defaults.removedTextColor
    }

    func apply(_ snapshot: AppSettingsSnapshot) {
        apply(
            DiffAppearanceSettingsDraft(
                fontName: snapshot.diffFontName,
                fontSize: snapshot.diffFontSize,
                addedBackgroundColor: Self.color(
                    hexString: snapshot.diffAddedBackgroundColor,
                    fallback: Defaults.addedBackgroundColor
                ),
                addedTextColor: Self.color(
                    hexString: snapshot.diffAddedTextColor,
                    fallback: Defaults.addedTextColor
                ),
                removedBackgroundColor: Self.color(
                    hexString: snapshot.diffRemovedBackgroundColor,
                    fallback: Defaults.removedBackgroundColor
                ),
                removedTextColor: Self.color(
                    hexString: snapshot.diffRemovedTextColor,
                    fallback: Defaults.removedTextColor
                )
            )
        )
    }

    static var defaultDraft: DiffAppearanceSettingsDraft {
        DiffAppearanceSettingsDraft(
            fontName: defaultFontName,
            fontSize: defaultFontSize,
            addedBackgroundColor: Defaults.addedBackgroundColor,
            addedTextColor: Defaults.addedTextColor,
            removedBackgroundColor: Defaults.removedBackgroundColor,
            removedTextColor: Defaults.removedTextColor
        )
    }

    // Upgrade the previous opaque defaults without replacing custom palettes.
    private static func updatedBackground(_ color: NSColor, added: Bool) -> NSColor {
        let previous = added ? "#E6FAF0FF" : "#FFEDE8FF"
        guard hexString(from: color) == previous else { return color }
        return added ? Defaults.addedBackgroundColor : Defaults.removedBackgroundColor
    }

    static func resolvedTextColor(_ color: NSColor, added: Bool, dark: Bool) -> NSColor {
        let defaultColor = added ? Defaults.addedTextColor : Defaults.removedTextColor
        guard dark, hexString(from: color) == hexString(from: defaultColor) else { return color }
        return added
            ? NSColor(srgbRed: 0.35, green: 0.90, blue: 0.66, alpha: 1)
            : NSColor(srgbRed: 1, green: 0.48, blue: 0.40, alpha: 1)
    }

    private func save(_ color: NSColor, forKey key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: color, requiringSecureCoding: true
        ) else { return }
        userDefaults.set(data, forKey: key)
    }

    private static func color(storedIn defaults: UserDefaults, key: String, fallback: NSColor) -> NSColor {
        guard let data = defaults.data(forKey: key),
              let color = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSColor.self, from: data
              ) else { return fallback }
        return color
    }

    private static func hexString(from color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#000000FF" }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
            .map { Int(round(min(max($0, 0), 1) * 255)) }
        return String(format: "#%02X%02X%02X%02X", arguments: components)
    }

    private static func color(hexString: String, fallback: NSColor) -> NSColor {
        let value = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard value.count == 8, let rgba = UInt64(value, radix: 16) else { return fallback }
        return NSColor(
            srgbRed: CGFloat((rgba >> 24) & 0xFF) / 255,
            green: CGFloat((rgba >> 16) & 0xFF) / 255,
            blue: CGFloat((rgba >> 8) & 0xFF) / 255,
            alpha: CGFloat(rgba & 0xFF) / 255
        )
    }
}
