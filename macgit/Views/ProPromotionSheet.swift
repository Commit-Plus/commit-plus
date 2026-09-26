// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

struct ProPromotionSheet: View {
    let promotion: ProPromotion
    let onUpgrade: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false

    private var isDark: Bool { colorScheme == .dark }

    private var accent: LinearGradient {
        LinearGradient(
            colors: isDark
                ? [.cyan, .indigo, .purple]
                : [
                    Color(red: 0.24, green: 0.68, blue: 0.94),
                    Color(red: 0.22, green: 0.48, blue: 0.82),
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryForeground: Color {
        isDark ? .white : Color(red: 0.08, green: 0.14, blue: 0.24)
    }

    private var secondaryForeground: Color {
        isDark ? .white.opacity(0.8) : Color(red: 0.20, green: 0.29, blue: 0.40)
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Label("COMMIT+ PRO", systemImage: "sparkles")
                    .font(.caption.bold())
                    .tracking(2)
                Spacer()
                Button("Close promotion", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .padding(8)
                    .background(primaryForeground.opacity(0.10), in: Circle())
            }
            .foregroundStyle(isDark ? .white.opacity(0.85) : Color.accentColor)

            VStack(spacing: 8) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(accent, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.3)))
                    .shadow(color: (isDark ? Color.indigo : Color.accentColor).opacity(isDark ? 0.5 : 0.25), radius: 24, y: 8)
                    .accessibilityHidden(true)
                Text("SAVE")
                    .font(.callout.bold())
                    .tracking(5)
                    .foregroundStyle(isDark ? .white.opacity(0.75) : Color.accentColor.opacity(0.8))
                    .padding(.top, 12)
                Text("\(promotion.save)%")
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .tracking(-4)
                    .foregroundStyle(LinearGradient(
                        colors: isDark
                            ? [.white, Color(red: 0.65, green: 0.85, blue: 1)]
                            : [Color(red: 0.10, green: 0.38, blue: 0.70), Color(red: 0.27, green: 0.65, blue: 0.90)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .shadow(color: Color.accentColor.opacity(isDark ? 0.25 : 0.12), radius: 20)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Save \(promotion.save) percent")

            VStack(spacing: 10) {
                Text(promotion.title)
                    .font(.title2.bold())
                    .foregroundStyle(primaryForeground)
                Text(promotion.description)
                    .font(.body)
                    .foregroundStyle(secondaryForeground)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR PROMO CODE")
                        .font(.caption.bold())
                        .tracking(1.5)
                        .foregroundStyle(secondaryForeground.opacity(0.85))
                    Text(promotion.code)
                        .font(.title3.monospaced().bold())
                        .foregroundStyle(primaryForeground)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(promotion.code, forType: .string)
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.callout.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            isDark ? Color.white.opacity(0.12) : Color.accentColor.opacity(0.12),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(isDark ? .white : Color.accentColor)
                .accessibilityLabel(copied ? "Code copied" : "Copy promotion code")
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        isDark
                            ? .white.opacity(reduceTransparency ? 0.15 : 0.07)
                            : .white.opacity(reduceTransparency ? 0.90 : 0.56)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18).strokeBorder(
                    isDark ? .white.opacity(0.18) : Color.accentColor.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
            )

            VStack(spacing: 14) {
                Button {
                    dismiss()
                    onUpgrade()
                } label: {
                    HStack(spacing: 10) {
                        Text("Get Pro").bold()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(accent, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                Button("Maybe later", role: .cancel) { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(secondaryForeground)
                    .keyboardShortcut(.cancelAction)
                if let endAt = promotion.endAt {
                    Text("Offer ends \(endAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.callout)
                        .foregroundStyle(secondaryForeground)
                }
            }
        }
        .padding(32)
        .frame(width: 500)
        .background {
            promotionBackground
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24).strokeBorder(
                isDark ? .white.opacity(0.15) : Color.accentColor.opacity(0.18)
            )
        )
    }

    @ViewBuilder
    private var promotionBackground: some View {
        ZStack {
            if isDark {
                Color(red: 0.055, green: 0.065, blue: 0.13)
            } else {
                Color(red: 0.93, green: 0.96, blue: 0.99)
            }

            if !reduceTransparency {
                Ellipse()
                    .fill(
                        isDark
                            ? Color.indigo.opacity(0.65)
                            : Color(red: 0.34, green: 0.62, blue: 0.90).opacity(0.24)
                    )
                    .frame(width: 360, height: 320)
                    .blur(radius: 70)
                    .offset(x: -170, y: -180)
                Ellipse()
                    .fill(
                        isDark
                            ? Color.cyan.opacity(0.25)
                            : Color(red: 0.58, green: 0.82, blue: 0.98).opacity(0.30)
                    )
                    .frame(width: 300, height: 280)
                    .blur(radius: 65)
                    .offset(x: 180, y: 70)
                Rectangle().fill(.ultraThinMaterial.opacity(isDark ? 0.2 : 0.42))
            }
        }
    }
}
