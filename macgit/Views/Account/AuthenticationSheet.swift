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

import AppKit
import SwiftUI

struct AuthenticationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: AccountSessionController
    @State private var mode: AuthenticationMode
    @State private var email = ""
    @State private var password = ""
    @State private var showingDeviceRecovery = false
    @State private var showingPassword = false
    @State private var emailValidationMessage: String?
    @State private var isEmailValid = false
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    init(controller: AccountSessionController, mode: AuthenticationMode) {
        self.controller = controller
        _mode = State(initialValue: mode)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            if controller.pendingLinkEmail == nil {
                Picker("Account action", selection: $mode) {
                    Text("Login").tag(AuthenticationMode.signIn)
                    Text("Sign Up").tag(AuthenticationMode.createAccount)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onContinuousHover { updateCursor($0, enabled: !controller.isLoading) }
                .disabled(controller.isLoading)
                .onChange(of: mode) {
                    controller.errorMessage = nil
                    emailValidationMessage = nil
                    showingPassword = false
                    password = ""
                }
            } else {
                Text("Enter the password for your existing Commit+ account. Google will be linked to the same account.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Email")
                    .font(.headline)
                TextField("Your email address", text: $email)
                    .textContentType(.emailAddress)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($emailFocused)
                    .disabled(controller.pendingLinkEmail != nil || controller.isLoading)
                    .onSubmit(submit)
                    .onChange(of: emailFocused) { _, isFocused in
                        if !isFocused, controller.pendingLinkEmail == nil {
                            validateEmail()
                        }
                    }
                    .onChange(of: email) {
                        emailValidationMessage = nil
                        isEmailValid = false
                        if controller.pendingLinkEmail == nil {
                            showingPassword = false
                            password = ""
                            // Avoid publishing a shared account update on every keystroke.
                            if controller.errorMessage != nil {
                                controller.errorMessage = nil
                            }
                        }
                    }

                if let emailValidationMessage {
                    Text(emailValidationMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Error: \(emailValidationMessage)")
                }

                if showingPassword || controller.pendingLinkEmail != nil {
                    Text("Password")
                        .font(.headline)
                        .padding(.top, 6)
                    SecureField("Your password", text: $password)
                        .textContentType(mode == .createAccount && controller.pendingLinkEmail == nil ? .newPassword : .password)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .focused($passwordFocused)
                        .disabled(controller.isLoading)
                        .onSubmit(submit)

                    if mode == .signIn, controller.pendingLinkEmail == nil {
                        Button("Forgot Password?", action: sendPasswordReset)
                            .buttonStyle(.link)
                            .onContinuousHover {
                                updateCursor($0, enabled: isEmailValid && !controller.isLoading)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .disabled(!isEmailValid || controller.isLoading)
                    } else if controller.pendingLinkEmail == nil {
                        Text("Use at least 6 characters.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage = controller.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Error: \(errorMessage)")
            }

            if mode == .signIn, let passwordResetMessage = controller.passwordResetMessage {
                Label(passwordResetMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if controller.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(primaryActionTitle)
                }
                .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(primaryActionDisabled)
            .onContinuousHover { updateCursor($0, enabled: !primaryActionDisabled) }

            if controller.pendingLinkEmail == nil {
                HStack(spacing: 12) {
                    Rectangle().frame(height: 1).foregroundStyle(.separator)
                    Text("or").foregroundStyle(.secondary)
                    Rectangle().frame(height: 1).foregroundStyle(.separator)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Or")

                VStack(spacing: 12) {
                    Button(action: signInWithGoogle) {
                        Label {
                            Text("Continue with Google")
                        } icon: {
                            Image("google")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                        }
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .onContinuousHover {
                        updateCursor($0, enabled: !controller.isLoading && controller.cloudFeaturesAvailable)
                    }
                    Button(action: controller.signInOnWeb) {
                        Label {
                            Text("Continue on web")
                        } icon: {
                            Image("commitplus-logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                        }
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .onContinuousHover {
                        updateCursor($0, enabled: !controller.isLoading && controller.cloudFeaturesAvailable)
                    }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .controlSize(.large)
                .disabled(controller.isLoading || !controller.cloudFeaturesAvailable)
            }

            Text("You can keep using Commit+ and all local Git features without an account.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(width: 440)
        .overlay(alignment: .topTrailing) {
            Button(action: cancel) {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .padding(8)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .onContinuousHover { updateCursor($0, enabled: !controller.isLoading) }
                .keyboardShortcut(.cancelAction)
                .help("Close")
                .disabled(controller.isLoading)
                .padding(8)
        }
        .interactiveDismissDisabled(controller.isLoading)
        .onAppear(perform: populatePendingLinkEmail)
        .onChange(of: controller.pendingLinkEmail) {
            populatePendingLinkEmail()
        }
        .onChange(of: controller.account?.uid) { _, accountUID in
            if accountUID != nil {
                dismiss()
            }
        }
        .onChange(of: controller.deviceAccessState) { _, state in
            switch state {
            case .limitReached, .failed:
                showingDeviceRecovery = true
            default:
                showingDeviceRecovery = false
            }
        }
        .sheet(isPresented: $showingDeviceRecovery) {
            DeviceLimitSheet(controller: controller)
        }
    }

    private var title: String {
        if controller.pendingLinkEmail != nil {
            "Link Google Account"
        } else {
            mode == .signIn ? "Login" : "Sign Up"
        }
    }

    private var primaryActionTitle: String {
        if controller.pendingLinkEmail != nil {
            "Link Account"
        } else if !showingPassword {
            "Continue"
        } else {
            mode == .signIn ? "Login" : "Sign Up"
        }
    }

    @discardableResult
    private func validateEmail() -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        isEmailValid = trimmedEmail.range(
            of: #"^[A-Z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Z0-9!#$%&'*+/=?^_`{|}~-]+)*@[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?)+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        emailValidationMessage = trimmedEmail.isEmpty || isEmailValid
            ? nil
            : "Enter a valid email address."
        return isEmailValid
    }

    private var primaryActionDisabled: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || ((showingPassword || controller.pendingLinkEmail != nil) && password.count < 6)
            || controller.isLoading
            || !controller.cloudFeaturesAvailable
    }

    private func updateCursor(_ phase: HoverPhase, enabled: Bool) {
        switch phase {
        case .active:
            (enabled ? NSCursor.pointingHand : NSCursor.arrow).set()
        case .ended:
            NSCursor.arrow.set()
        }
    }

    private func submit() {
        guard !primaryActionDisabled else { return }
        guard controller.pendingLinkEmail != nil || validateEmail() else { return }
        if !showingPassword && controller.pendingLinkEmail == nil {
            showingPassword = true
            passwordFocused = true
            return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if controller.pendingLinkEmail != nil {
                await controller.completePendingLink(password: password)
            } else if mode == .signIn {
                await controller.signIn(email: trimmedEmail, password: password)
            } else {
                await controller.createAccount(email: trimmedEmail, password: password)
            }
        }
    }

    private func sendPasswordReset() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await controller.sendPasswordReset(email: trimmedEmail)
        }
    }

    private func signInWithGoogle() {
        Task {
            await controller.signInWithGoogle()
        }
    }

    private func cancel() {
        controller.cancelWebSignIn()
        controller.presentedSheet = nil
        dismiss()
    }

    private func populatePendingLinkEmail() {
        if let pendingLinkEmail = controller.pendingLinkEmail {
            email = pendingLinkEmail
            password = ""
        }
    }
}
