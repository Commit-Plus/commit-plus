//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import SwiftUI

struct AIProviderMenu: View {
    enum LabelMode {
        case provider
        case model
    }

    @ObservedObject var controller: AIProviderController
    let restrictedProviderAccess: FeatureAccessDecision
    let showsConfigureAction: Bool
    let labelMode: LabelMode

    init(
        controller: AIProviderController,
        restrictedProviderAccess: FeatureAccessDecision,
        showsConfigureAction: Bool,
        labelMode: LabelMode = .provider
    ) {
        self.controller = controller
        self.restrictedProviderAccess = restrictedProviderAccess
        self.showsConfigureAction = showsConfigureAction
        self.labelMode = labelMode
    }

    var body: some View {
        Menu {
            ForEach(controller.descriptors) { descriptor in
                Button {
                    controller.selectProvider(descriptor.id)
                } label: {
                    Label {
                        Text(menuTitle(for: descriptor))
                    } icon: {
                        Image(systemName: descriptor.id == controller.selectedProviderID
                            ? "checkmark"
                            : descriptor.systemImage)
                    }
                }
                .disabled(
                    !controller.canSelect(
                        descriptor,
                        restrictedProviderAccess: restrictedProviderAccess
                    ) || controller.isGenerating
                )
                .help(menuHelp(for: descriptor))
            }

            if showsConfigureAction {
                Divider()

                Button("Configure", systemImage: "gearshape", action: openAIProviderSettings)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: controller.selectedProviderAvailability.isAvailable
                    ? "sparkles"
                    : "exclamationmark.triangle")
                    .font(.system(size: 10, weight: .medium))
                Text(labelTitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .buttonStyle(GlassButtonStyle(tint: .secondary, fontSize: 10))
        .disabled(controller.isGenerating)
        .help(providerHelp)
    }

    private var labelTitle: String {
        switch labelMode {
        case .provider:
            controller.selectedDescriptor.displayName
        case .model:
            controller.model(for: controller.selectedDescriptor)
                ?? controller.selectedDescriptor.displayName
        }
    }

    private var providerHelp: String {
        let descriptor = controller.selectedDescriptor
        let availability = controller.selectedProviderAvailability
        if let model = controller.model(for: descriptor) {
            return "Cloud · \(model) · \(availability.detail)"
        }
        return "\(descriptor.detail) · \(availability.detail)"
    }

    private func menuTitle(for descriptor: AIProviderDescriptor) -> String {
        if descriptor.billing == .commitPlus { return "\(descriptor.displayName) — Pro" }
        if descriptor.id == .appleIntelligence {
            return "\(descriptor.displayName) — On-device"
        }
        return "\(descriptor.displayName) — \(controller.model(for: descriptor) ?? "Default")"
    }

    private func menuHelp(for descriptor: AIProviderDescriptor) -> String {
        if descriptor.billing == .commitPlus {
            return controller.canSelect(descriptor, restrictedProviderAccess: restrictedProviderAccess)
                ? controller.availability(for: descriptor.id).detail
                : "Sign in with an active Commit+ Pro subscription to use Commit+ AI."
        }
        if controller.canSelect(
            descriptor,
            restrictedProviderAccess: restrictedProviderAccess
        ) {
            return controller.availability(for: descriptor.id).detail
        }
        if descriptor.requiresProToConfigureAPIKey,
           !restrictedProviderAccess.isAllowed {
            return "Commit+ Pro required to use this provider."
        }
        if descriptor.billing == .bringYourOwnKey,
           !controller.isAPIKeyConfigured(for: descriptor.id) {
            return "Configure an API key in Settings → AI Providers."
        }
        return controller.availability(for: descriptor.id).detail
    }

    private func openAIProviderSettings() {
        WindowScopedNotification.post(
            name: .showAppSettings,
            userInfo: ["section": AppSettingsSection.aiProviders.rawValue]
        )
    }
}
