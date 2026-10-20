// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct AboutCommitPlusView: View {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(applicationName)
                    .font(.headline)
                    .bold()

                Text(versionDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                if let websiteURL {
                    Link("Website", destination: websiteURL)
                }

                if let xURL {
                    Link("X", destination: xURL)
                }
            }

            Text(copyright)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 360)
    }

    private var applicationName: String {
        bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Commit+"
    }

    private var versionDescription: String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "Version \(version) (\(build))"
    }

    private var copyright: String {
        bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }

    private var websiteURL: URL? {
        try? CommitPlusWebConfiguration.baseURL(bundle: bundle)
    }

    private var xURL: URL? {
        try? CommitPlusWebConfiguration.socialURL()
    }
}
