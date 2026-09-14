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
import Foundation

nonisolated enum CommitPlusAIError: Error, LocalizedError, Sendable {
    case unavailable, invalidResponse, sessionChanged, signedOut
    case server(code: String)
    case outputLost, outcomeUnknown
    var errorDescription: String? {
        switch self {
        case .unavailable: "Commit+ AI is unavailable. Try again later or choose another provider."
        case .invalidResponse: "Commit+ AI returned an incomplete response. Check usage before starting a new request."
        case .sessionChanged: "Your account changed. Start a new request with your current account."
        case .signedOut: "Sign in with an active Commit+ Pro subscription to use Commit+ AI."
        case .outcomeUnknown: "The connection ended before this request could be confirmed. Check usage before sending again; a new request may use additional credits."
        case .outputLost: "This request completed, but its response could not be recovered. Starting a new request may use additional credits."
        case .server(let code):
            switch code {
            case "unauthenticated", "pro_required": "Sign in with an active Commit+ Pro subscription to use Commit+ AI."
            case "credits_exhausted": "Your available AI credits cannot cover this request. Check usage in Settings or choose another provider."
            case "accounting_pending", "request_in_progress": "This AI request is still being accounted for. Its credits remain reserved; do not resend it automatically."
            case "request_already_completed": "This request already completed. A new request may use additional credits."
            case "rate_limited": "Please wait before sending another AI request."
            default: "Commit+ AI could not complete the request. Try again later."
            }
        }
    }
}
