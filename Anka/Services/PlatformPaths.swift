//
//  PlatformPaths.swift
//  Anka
//
//  Centralizes platform-specific storage paths. Anka is iOS-only at MVP,
//  but the macOS branch is preserved so ports from Spendy compile cleanly.
//

import Foundation

public enum PlatformPaths {
    /// App Group suite identifier (iOS) / namespace folder name (macOS).
    public static let appGroupID: String = {
        #if os(macOS)
        return "nc.Anka"
        #else
        return "group.com.nc.anka"
        #endif
    }()

    /// Directory holding the SwiftData store + shared files (ML model, corrections).
    public static var appGroupContainerURL: URL {
        #if os(macOS)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("nc.Anka", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #else
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
    }

    /// Shared UserDefaults (used by widgets/intents on iOS).
    public static var sharedDefaults: UserDefaults {
        #if os(macOS)
        return UserDefaults.standard
        #else
        return UserDefaults(suiteName: appGroupID) ?? .standard
        #endif
    }
}
