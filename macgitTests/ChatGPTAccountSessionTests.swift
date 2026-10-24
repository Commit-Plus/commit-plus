// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest
@testable import macgit

final class ChatGPTAccountSessionTests: XCTestCase {
    private let redirectURI = URL(string: "http://127.0.0.1:1455/auth/callback")!

    func testFirstSignInUsesDynamicRegistrationAndPlanScopes() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let session = ChatGPTAccountSession(store: store, httpClient: ChatGPTStubHTTPClient())

        let url = try await session.beginAuthorization(redirectURI: redirectURI)
        let items = queryItems(url)

        XCTAssertEqual(url.host, "auth.openai.com")
        XCTAssertEqual(url.path, "/api/accounts/authorize")
        XCTAssertEqual(items["client_id"], "dynamic_agent_client")
        XCTAssertEqual(items["agent_name_hint"], "Commit+")
        XCTAssertEqual(items["ext_agent_host_id"], try store.loadRegistration()?.hostID)
        XCTAssertTrue(items["ext_agent_host_id"]?.hasPrefix("urn:uuid:") == true)
        XCTAssertEqual(items["scope"], "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
        XCTAssertEqual(items["resource"], "https://api.openai.com/v1")
        XCTAssertEqual(items["redirect_uri"], "http://127.0.0.1:1455/auth/callback")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertNotNil(items["state"])
        XCTAssertNotNil(items["nonce"])
        XCTAssertNotNil(items["code_challenge"])
        XCTAssertNil(items["login_hint"])
    }

    func testLaterSignInReusesIssuedClientID() async throws {
        let store = InMemoryChatGPTCredentialStore(
            registration: ChatGPTRegistration(hostID: "urn:uuid:host", clientID: "oaiapp_saved", email: "dev@example.com")
        )
        let session = ChatGPTAccountSession(store: store, httpClient: ChatGPTStubHTTPClient())

        let items = queryItems(try await session.beginAuthorization(redirectURI: redirectURI))

        XCTAssertEqual(items["client_id"], "oaiapp_saved")
        XCTAssertNil(items["agent_name_hint"])
        XCTAssertEqual(items["ext_agent_host_id"], "urn:uuid:host")
        XCTAssertEqual(items["login_hint"], "dev@example.com")
    }

    func testAnotherAccountRegistersNewClientAndReplacesSavedOne() async throws {
        let store = InMemoryChatGPTCredentialStore(
            registration: ChatGPTRegistration(hostID: "urn:uuid:host", clientID: "oaiapp_saved", email: "old@example.com")
        )
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: store, httpClient: http)
        let returning = await session.returningAccount()
        XCTAssertEqual(returning, ChatGPTReturningAccount(email: "old@example.com"))

        let items = queryItems(try await session.beginAuthorization(redirectURI: redirectURI, newAccount: true))

        XCTAssertEqual(items["client_id"], "dynamic_agent_client")
        XCTAssertEqual(items["agent_name_hint"], "Commit+")
        XCTAssertEqual(items["ext_agent_host_id"], "urn:uuid:host")
        XCTAssertNil(items["login_hint"])
        XCTAssertEqual(try store.loadRegistration()?.clientID, "oaiapp_saved")
        let state = try XCTUnwrap(items["state"])
        let nonce = try XCTUnwrap(items["nonce"])
        await http.respond(to: "/api/accounts/oauth/token", body: tokenResponse(clientID: "oaiapp_new", nonce: nonce))

        _ = try await session.completeAuthorization(callbackURL: callback(state: state, extra: "&client_id=oaiapp_new"))

        XCTAssertEqual(try store.loadRegistration()?.clientID, "oaiapp_new")
        XCTAssertEqual(try store.loadTokens()?.clientID, "oaiapp_new")
    }

    func testFailedAnotherAccountSignInKeepsSavedRegistration() async throws {
        let saved = ChatGPTRegistration(hostID: "urn:uuid:host", clientID: "oaiapp_saved", email: "old@example.com")
        let store = InMemoryChatGPTCredentialStore(registration: saved)
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: store, httpClient: http)

        for (status, body) in [
            (200, tokenResponse(clientID: "oaiapp_new", nonce: "unused", scope: "openid email offline_access")),
            (401, #"{"error":"invalid_client","error_description":"Unknown client"}"#),
        ] {
            let items = queryItems(try await session.beginAuthorization(redirectURI: redirectURI, newAccount: true))
            await http.respond(to: "/api/accounts/oauth/token", status: status, body: body)
            do {
                _ = try await session.completeAuthorization(
                    callbackURL: callback(state: try XCTUnwrap(items["state"]), extra: "&client_id=oaiapp_new")
                )
                XCTFail("The token exchange must fail")
            } catch is ChatGPTAuthError {}
            XCTAssertEqual(try store.loadRegistration(), saved)
            XCTAssertNil(try store.loadTokens())
        }
    }

    func testReturningSignInRejectsDifferentIssuedClientID() async throws {
        let store = InMemoryChatGPTCredentialStore(
            registration: ChatGPTRegistration(hostID: "urn:uuid:host", clientID: "oaiapp_saved", email: nil)
        )
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: store, httpClient: http)
        let items = queryItems(try await session.beginAuthorization(redirectURI: redirectURI))

        do {
            _ = try await session.completeAuthorization(
                callbackURL: callback(state: try XCTUnwrap(items["state"]), extra: "&client_id=oaiapp_other")
            )
            XCTFail("A different issued client ID must be rejected")
        } catch {
            XCTAssertEqual(error as? ChatGPTAuthError, .missingClientID)
        }
        XCTAssertNil(try store.loadTokens())
        XCTAssertEqual(try store.loadRegistration()?.clientID, "oaiapp_saved")
        let requests = await http.allRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testSuccessfulSignInStoresTokensFromKeychainOnly() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: store, httpClient: http)
        let defaultsBefore = Set(UserDefaults.standard.dictionaryRepresentation().keys)

        let authorizeURL = try await session.beginAuthorization(redirectURI: redirectURI)
        let items = queryItems(authorizeURL)
        await http.respond(to: "/api/accounts/oauth/token", body: tokenResponse(
            clientID: "oaiapp_new",
            nonce: try XCTUnwrap(items["nonce"])
        ))
        let account = try await session.completeAuthorization(
            callbackURL: callback(state: try XCTUnwrap(items["state"]), extra: "&client_id=oaiapp_new")
        )

        XCTAssertEqual(account.email, "dev@example.com")
        let tokens = try XCTUnwrap(try store.loadTokens())
        XCTAssertEqual(tokens.clientID, "oaiapp_new")
        XCTAssertEqual(tokens.accessToken, "access-1")
        XCTAssertEqual(tokens.refreshToken, "refresh-1")
        XCTAssertEqual(try store.loadRegistration()?.clientID, "oaiapp_new")
        let exchangeRequests = await http.requests(path: "/api/accounts/oauth/token")
        let exchange = try XCTUnwrap(exchangeRequests.first)
        let form = formFields(exchange)
        XCTAssertEqual(form["grant_type"], "authorization_code")
        XCTAssertEqual(form["client_id"], "oaiapp_new")
        XCTAssertEqual(form["redirect_uri"], redirectURI.absoluteString)
        XCTAssertNotNil(form["code_verifier"])

        let newKeys = Set(UserDefaults.standard.dictionaryRepresentation().keys).subtracting(defaultsBefore)
        XCTAssertFalse(newKeys.contains { $0.lowercased().contains("chatgpt") })
        let defaultsValues = UserDefaults.standard.dictionaryRepresentation().values.map { "\($0)" }
        XCTAssertFalse(defaultsValues.contains { $0.contains("access-1") || $0.contains("refresh-1") })
    }

    func testMismatchedStateIsIgnoredAndStoresNoTokens() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: store, httpClient: http)
        let items = queryItems(try await session.beginAuthorization(redirectURI: redirectURI))

        do {
            _ = try await session.completeAuthorization(callbackURL: callback(state: "forged", extra: "&client_id=oaiapp_x"))
            XCTFail("A mismatched state must be rejected")
        } catch let error as GitProviderOAuthError {
            XCTAssertEqual(error, .stateMismatch)
        }
        XCTAssertNil(try store.loadTokens())
        let tokenRequests = await http.requests(path: "/api/accounts/oauth/token")
        XCTAssertTrue(tokenRequests.isEmpty)

        // The genuine callback still completes the pending sign-in.
        await http.respond(to: "/api/accounts/oauth/token", body: tokenResponse(
            clientID: "oaiapp_x",
            nonce: try XCTUnwrap(items["nonce"])
        ))
        _ = try await session.completeAuthorization(
            callbackURL: callback(state: try XCTUnwrap(items["state"]), extra: "&client_id=oaiapp_x")
        )
        XCTAssertNotNil(try store.loadTokens())
    }

    func testDeniedConsentStoresNoTokens() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let session = ChatGPTAccountSession(store: store, httpClient: ChatGPTStubHTTPClient())
        let items = queryItems(try await session.beginAuthorization(redirectURI: redirectURI))
        let state = try XCTUnwrap(items["state"])

        do {
            _ = try await session.completeAuthorization(
                callbackURL: URL(string: "\(redirectURI.absoluteString)?error=access_denied&state=\(state)")!
            )
            XCTFail("Denied consent must not sign in")
        } catch let error as ChatGPTAuthError {
            XCTAssertEqual(error, .consentDenied)
        }
        XCTAssertNil(try store.loadTokens())
        let account = await session.account()
        XCTAssertNil(account)
    }

    func testErrorCallbackWithoutMatchingStateKeepsSignInPending() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: store, httpClient: http)
        let items = queryItems(try await session.beginAuthorization(redirectURI: redirectURI))

        for forged in ["?error=access_denied", "?error=access_denied&state=forged"] {
            do {
                _ = try await session.completeAuthorization(
                    callbackURL: URL(string: "\(redirectURI.absoluteString)\(forged)")!
                )
                XCTFail("An error callback without the pending state must be rejected")
            } catch let error as GitProviderOAuthError {
                XCTAssertTrue([.stateMismatch, .missingState].contains(error), "Unexpected \(error)")
            }
        }

        await http.respond(to: "/api/accounts/oauth/token", body: tokenResponse(
            clientID: "oaiapp_x",
            nonce: try XCTUnwrap(items["nonce"])
        ))
        _ = try await session.completeAuthorization(
            callbackURL: callback(state: try XCTUnwrap(items["state"]), extra: "&client_id=oaiapp_x")
        )
        XCTAssertNotNil(try store.loadTokens())
    }

    func testMissingPlanUsageScopeStoresNoTokens() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: store, httpClient: http)
        let items = queryItems(try await session.beginAuthorization(redirectURI: redirectURI))
        await http.respond(to: "/api/accounts/oauth/token", body: tokenResponse(
            clientID: "oaiapp_new",
            nonce: try XCTUnwrap(items["nonce"]),
            scope: "openid profile email offline_access"
        ))

        do {
            _ = try await session.completeAuthorization(
                callbackURL: callback(state: try XCTUnwrap(items["state"]), extra: "&client_id=oaiapp_new")
            )
            XCTFail("Identity-only sign-in must not enable plan usage")
        } catch let error as ChatGPTAuthError {
            XCTAssertEqual(error, .planScopeNotGranted)
        }
        XCTAssertNil(try store.loadTokens())
        let availability = await session.availability()
        XCTAssertFalse(availability.isAvailable)
    }

    func testIDTokenWithWrongNonceIsRejected() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: store, httpClient: http)
        let items = queryItems(try await session.beginAuthorization(redirectURI: redirectURI))
        await http.respond(to: "/api/accounts/oauth/token", body: tokenResponse(clientID: "oaiapp_new", nonce: "other"))

        do {
            _ = try await session.completeAuthorization(
                callbackURL: callback(state: try XCTUnwrap(items["state"]), extra: "&client_id=oaiapp_new")
            )
            XCTFail("An ID token for another request must be rejected")
        } catch let error as ChatGPTAuthError {
            XCTAssertEqual(error, .invalidIDToken)
        }
        XCTAssertNil(try store.loadTokens())
    }

    func testConcurrentRequestsShareOneRefreshAndSaveRotatedToken() async throws {
        let clock = ChatGPTTestClock()
        let store = InMemoryChatGPTCredentialStore(tokens: .expiring(at: clock.now.addingTimeInterval(60)))
        let http = ChatGPTStubHTTPClient(delay: 50_000_000)
        await http.respond(to: "/api/accounts/oauth/token", body: """
            {"access_token":"access-2","refresh_token":"refresh-2","expires_in":3600,"token_type":"Bearer"}
            """)
        let session = ChatGPTAccountSession(store: store, httpClient: http, now: { clock.now })

        async let first = session.accessToken()
        async let second = session.accessToken()
        async let third = session.accessToken()
        let tokens = try await [first, second, third]

        XCTAssertEqual(tokens, ["access-2", "access-2", "access-2"])
        let refreshes = await http.requests(path: "/api/accounts/oauth/token")
        XCTAssertEqual(refreshes.count, 1)
        let form = formFields(try XCTUnwrap(refreshes.first))
        XCTAssertEqual(form["grant_type"], "refresh_token")
        XCTAssertEqual(form["refresh_token"], "refresh-1")
        XCTAssertEqual(form["client_id"], "oaiapp_test")
        XCTAssertNil(form["scope"])
        XCTAssertEqual(try store.loadTokens()?.refreshToken, "refresh-2")
    }

    func testRejectedRefreshClearsTokensAndRequiresSignIn() async throws {
        let clock = ChatGPTTestClock()
        let store = InMemoryChatGPTCredentialStore(tokens: .expiring(at: clock.now.addingTimeInterval(-10)))
        let http = ChatGPTStubHTTPClient()
        await http.respond(to: "/api/accounts/oauth/token", status: 400, body: """
            {"error":"invalid_grant","error_description":"Refresh token revoked"}
            """)
        let session = ChatGPTAccountSession(store: store, httpClient: http, now: { clock.now })

        do {
            _ = try await session.accessToken()
            XCTFail("A revoked refresh token must require sign-in")
        } catch let error as CommitMessageGenerationError {
            XCTAssertEqual(error, .chatGPTSignInRequired)
        }
        XCTAssertNil(try store.loadTokens())
        let availability = await session.availability()
        XCTAssertEqual(availability, .unavailable("Sign in to ChatGPT in Settings → AI."))
    }

    func testDisconnectDuringRefreshDiscardsAndRevokesRotatedToken() async throws {
        let clock = ChatGPTTestClock()
        let store = InMemoryChatGPTCredentialStore(tokens: .expiring(at: clock.now.addingTimeInterval(60)))
        let http = ChatGPTStubHTTPClient(delay: 100_000_000)
        await http.respond(to: "/api/accounts/oauth/token", body: """
            {"access_token":"access-2","refresh_token":"refresh-2","expires_in":3600,"token_type":"Bearer"}
            """)
        await http.respond(to: "/.well-known/openid-configuration", body: """
            {"revocation_endpoint":"https://auth.openai.com/oauth/revoke"}
            """)
        let session = ChatGPTAccountSession(store: store, httpClient: http, now: { clock.now })

        let request = Task { try await session.accessToken() }
        while await http.requests(path: "/api/accounts/oauth/token").isEmpty {
            await Task.yield()
        }
        await session.disconnect()

        do {
            _ = try await request.value
            XCTFail("A refresh that finishes after disconnect must not sign in again")
        } catch let error as CommitMessageGenerationError {
            XCTAssertEqual(error, .chatGPTSignInRequired)
        }
        XCTAssertNil(try store.loadTokens())
        let account = await session.account()
        XCTAssertNil(account)
        let revoked = await http.requests(path: "/oauth/revoke").map { formFields($0)["token"] }
        XCTAssertEqual(Set(revoked.compactMap { $0 }), ["refresh-1", "refresh-2"])
    }

    func testUnexpiredTokenIsUsedWithoutRefresh() async throws {
        let clock = ChatGPTTestClock()
        let store = InMemoryChatGPTCredentialStore(tokens: .expiring(at: clock.now.addingTimeInterval(3_000)))
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: store, httpClient: http, now: { clock.now })

        let token = try await session.accessToken()

        XCTAssertEqual(token, "access-1")
        let requests = await http.allRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testDisconnectRevokesRefreshTokenAndKeepsRegistration() async throws {
        let store = InMemoryChatGPTCredentialStore(
            tokens: .expiring(at: Date().addingTimeInterval(3_000)),
            registration: ChatGPTRegistration(hostID: "urn:uuid:host", clientID: "oaiapp_test", email: "dev@example.com")
        )
        let http = ChatGPTStubHTTPClient()
        await http.respond(to: "/.well-known/openid-configuration", body: """
            {"revocation_endpoint":"https://auth.openai.com/oauth/revoke"}
            """)
        let session = ChatGPTAccountSession(store: store, httpClient: http)

        await session.disconnect()

        let revocationRequests = await http.requests(path: "/oauth/revoke")

        let revocation = try XCTUnwrap(revocationRequests.first)
        let form = formFields(revocation)
        XCTAssertEqual(form["token"], "refresh-1")
        XCTAssertEqual(form["token_type_hint"], "refresh_token")
        XCTAssertEqual(form["client_id"], "oaiapp_test")
        XCTAssertNil(try store.loadTokens())
        XCTAssertEqual(try store.loadRegistration()?.clientID, "oaiapp_test")
        let account = await session.account()
        XCTAssertNil(account)
    }

    func testLoopbackServerDeliversCallbackAndIgnoresOtherPaths() async throws {
        let server = try await ChatGPTLoopbackCallbackServer.start(preferredPort: 0, path: "/auth/callback")
        defer { server.stop() }
        XCTAssertEqual(server.redirectURI.host, "127.0.0.1")
        XCTAssertEqual(server.redirectURI.path, "/auth/callback")
        let port = try XCTUnwrap(server.redirectURI.port)

        let (_, notFound) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/favicon.ico")!)
        XCTAssertEqual((notFound as? HTTPURLResponse)?.statusCode, 404)
        let (_, ok) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:\(port)/auth/callback?code=abc&state=xyz")!
        )
        XCTAssertEqual((ok as? HTTPURLResponse)?.statusCode, 200)

        var iterator = server.callbacks.makeAsyncIterator()
        let next = await iterator.next()
        let received = try XCTUnwrap(next)
        XCTAssertEqual(received.path, "/auth/callback")
        XCTAssertEqual(URLComponents(url: received, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value, "abc")
    }

    // MARK: Codex flow

    private let codexRedirectURI = URL(string: "http://localhost:1455/auth/callback")!

    func testCodexAuthorizeURLUsesFixedClientWithoutRegistrationOrNonce() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let session = ChatGPTAccountSession(store: store, httpClient: ChatGPTStubHTTPClient(), configuration: .codex)

        let url = try await session.beginAuthorization(redirectURI: codexRedirectURI)
        let items = queryItems(url)

        XCTAssertEqual(url.host, "auth.openai.com")
        XCTAssertEqual(url.path, "/oauth/authorize")
        XCTAssertEqual(items["client_id"], "app_EMoamEEZ73f0CkXaXp7hrann")
        XCTAssertEqual(items["redirect_uri"], "http://localhost:1455/auth/callback")
        XCTAssertEqual(items["scope"], "openid profile email offline_access api.connectors.read api.connectors.invoke")
        XCTAssertEqual(items["id_token_add_organizations"], "true")
        XCTAssertEqual(items["codex_cli_simplified_flow"], "true")
        XCTAssertEqual(items["originator"], "codex_cli_rs")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertNotNil(items["state"])
        XCTAssertNil(items["nonce"])
        XCTAssertNil(items["resource"])
        XCTAssertNil(items["ext_agent_host_id"])
        XCTAssertNil(try store.loadRegistration())
        let returning = await session.returningAccount()
        XCTAssertNil(returning)
    }

    func testCodexCodeExchangeStoresAccountAndPlanWithoutNonce() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: store, httpClient: http, configuration: .codex)
        let items = queryItems(try await session.beginAuthorization(redirectURI: codexRedirectURI))
        await http.respond(to: "/oauth/token", body: codexTokenResponse(
            idToken: ChatGPTTestTokens.codexIDToken(accountID: "acct-1", planType: "free")
        ))

        let account = try await session.completeAuthorization(
            callbackURL: codexCallback(state: try XCTUnwrap(items["state"]))
        )

        XCTAssertEqual(account, ConnectedAIAccountSummary(email: "dev@example.com", planType: "free"))
        let tokens = try XCTUnwrap(try store.loadTokens())
        XCTAssertEqual(tokens.clientID, "app_EMoamEEZ73f0CkXaXp7hrann")
        XCTAssertEqual(tokens.accountID, "acct-1")
        XCTAssertEqual(tokens.planType, "free")
        let accountID = await session.chatGPTAccountID()
        XCTAssertEqual(accountID, "acct-1")
        let exchangeRequests = await http.requests(path: "/oauth/token")
        let form = formFields(try XCTUnwrap(exchangeRequests.first))
        XCTAssertEqual(form["grant_type"], "authorization_code")
        XCTAssertEqual(form["client_id"], "app_EMoamEEZ73f0CkXaXp7hrann")
        XCTAssertEqual(form["redirect_uri"], codexRedirectURI.absoluteString)
        XCTAssertNotNil(form["code_verifier"])
        XCTAssertNil(form["resource"])
    }

    func testCodexSignInWithoutAccountIDIsRejected() async throws {
        let store = InMemoryChatGPTCredentialStore()
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: store, httpClient: http, configuration: .codex)
        let items = queryItems(try await session.beginAuthorization(redirectURI: codexRedirectURI))
        await http.respond(to: "/oauth/token", body: codexTokenResponse(
            idToken: ChatGPTTestTokens.codexIDToken(accountID: "", planType: "plus")
        ))

        do {
            _ = try await session.completeAuthorization(callbackURL: codexCallback(state: try XCTUnwrap(items["state"])))
            XCTFail("A Codex sign-in without an account ID must be rejected")
        } catch let error as ChatGPTAuthError {
            XCTAssertEqual(error, .invalidIDToken)
        }
        XCTAssertNil(try store.loadTokens())
    }

    func testCodexRejectedClientReportsBlockedConnection() async throws {
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: InMemoryChatGPTCredentialStore(), httpClient: http, configuration: .codex)
        let items = queryItems(try await session.beginAuthorization(redirectURI: codexRedirectURI))
        await http.respond(to: "/oauth/token", status: 401, body: """
            {"error":"invalid_client","error_description":"Unknown client"}
            """)

        do {
            _ = try await session.completeAuthorization(callbackURL: codexCallback(state: try XCTUnwrap(items["state"])))
            XCTFail("A rejected client must fail the sign-in")
        } catch let error as ChatGPTAuthError {
            XCTAssertEqual(error, .clientRejected)
        }
    }

    func testCodexRefreshSendsScopeInsteadOfResource() async throws {
        let clock = ChatGPTTestClock()
        var expiring = ChatGPTTokenSet.expiring(at: clock.now.addingTimeInterval(60))
        expiring.clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
        let store = InMemoryChatGPTCredentialStore(tokens: expiring)
        let http = ChatGPTStubHTTPClient()
        await http.respond(to: "/oauth/token", body: """
            {"access_token":"access-2","refresh_token":"refresh-2","expires_in":3600}
            """)
        let session = ChatGPTAccountSession(store: store, httpClient: http, configuration: .codex, now: { clock.now })

        let token = try await session.accessToken()

        XCTAssertEqual(token, "access-2")
        let refreshes = await http.requests(path: "/oauth/token")
        let form = formFields(try XCTUnwrap(refreshes.first))
        XCTAssertEqual(form["grant_type"], "refresh_token")
        XCTAssertEqual(form["client_id"], "app_EMoamEEZ73f0CkXaXp7hrann")
        XCTAssertEqual(form["scope"], "openid profile email offline_access api.connectors.read api.connectors.invoke")
        XCTAssertNil(form["resource"])
    }

    func testCodexDisconnectRevokesAtFixedEndpointWithoutDiscovery() async throws {
        let store = InMemoryChatGPTCredentialStore(tokens: .expiring(at: Date().addingTimeInterval(3_000)))
        let http = ChatGPTStubHTTPClient()
        let session = ChatGPTAccountSession(store: store, httpClient: http, configuration: .codex)

        await session.disconnect()

        XCTAssertNil(try store.loadTokens())
        let revocations = await http.requests(path: "/oauth/revoke")
        XCTAssertEqual(formFields(try XCTUnwrap(revocations.first))["token"], "refresh-1")
        let discovery = await http.requests(path: "/.well-known/openid-configuration")
        XCTAssertTrue(discovery.isEmpty)
    }

    func testCodexAndOfficialKeychainItemsAreSeparate() {
        XCTAssertNotEqual(
            String(describing: KeychainChatGPTCredentialStore.codex),
            String(describing: KeychainChatGPTCredentialStore())
        )
    }

    // MARK: Loopback port

    func testRequiredLoopbackPortFailsWhenTaken() async throws {
        let occupied = try OccupiedLoopbackPort()
        defer { occupied.close() }

        do {
            let server = try await ChatGPTLoopbackCallbackServer.start(
                preferredPort: occupied.port,
                redirectHost: "localhost",
                requiresPreferredPort: true
            )
            server.stop()
            XCTFail("A required port that is in use must fail the sign-in")
        } catch let error as ChatGPTAuthError {
            XCTAssertEqual(error, .loopbackPortInUse(occupied.port))
            XCTAssertEqual(
                error.localizedDescription,
                "Port \(occupied.port) is in use. Close other ChatGPT sign-ins and try again."
            )
        }
    }

    func testOfficialLoopbackFallsBackToFreePortWhenTaken() async throws {
        let occupied = try OccupiedLoopbackPort()
        defer { occupied.close() }

        let server = try await ChatGPTLoopbackCallbackServer.start(preferredPort: occupied.port)
        defer { server.stop() }

        XCTAssertNotEqual(server.redirectURI.port, Int(occupied.port))
        XCTAssertEqual(server.redirectURI.host, "127.0.0.1")
    }

    func testCodexLoopbackNamesLocalhostAndDeliversCallback() async throws {
        let server = try await ChatGPTLoopbackCallbackServer.start(preferredPort: 0, redirectHost: "localhost")
        defer { server.stop() }
        XCTAssertEqual(server.redirectURI.host, "localhost")
        let port = try XCTUnwrap(server.redirectURI.port)

        _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/auth/callback?code=abc&state=xyz")!)

        var iterator = server.callbacks.makeAsyncIterator()
        let next = await iterator.next()
        let received = try XCTUnwrap(next)
        XCTAssertEqual(received.host, "localhost")
        XCTAssertEqual(received.port, port)
    }

    private func codexCallback(state: String) -> URL {
        URL(string: "\(codexRedirectURI.absoluteString)?code=auth-code&state=\(state)")!
    }

    private func codexTokenResponse(idToken: String) -> String {
        """
        {"access_token":"access-1","refresh_token":"refresh-1","id_token":"\(idToken)","token_type":"Bearer","expires_in":3600}
        """
    }

    // MARK: Helpers

    private func callback(state: String, extra: String = "") -> URL {
        URL(string: "\(redirectURI.absoluteString)?code=auth-code&state=\(state)&scope=chatgpt.tokens.use.direct\(extra)")!
    }

    private func tokenResponse(
        clientID: String,
        nonce: String,
        scope: String = "chatgpt.tokens.use.direct email offline_access openid profile resource.invoke"
    ) -> String {
        let idToken = ChatGPTTestTokens.idToken(clientID: clientID, nonce: nonce)
        return """
            {"access_token":"access-1","refresh_token":"refresh-1","id_token":"\(idToken)","token_type":"Bearer","expires_in":3600,"scope":"\(scope)"}
            """
    }

    private func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    private func formFields(_ request: URLRequest) -> [String: String] {
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        var components = URLComponents()
        components.percentEncodedQuery = body
        return Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

// MARK: Shared ChatGPT test support

final class InMemoryChatGPTCredentialStore: ChatGPTCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: ChatGPTTokenSet?
    private var registration: ChatGPTRegistration?

    init(tokens: ChatGPTTokenSet? = nil, registration: ChatGPTRegistration? = nil) {
        self.tokens = tokens
        self.registration = registration
    }

    func loadTokens() throws -> ChatGPTTokenSet? { lock.withLock { tokens } }
    func saveTokens(_ tokens: ChatGPTTokenSet) throws { lock.withLock { self.tokens = tokens } }
    func deleteTokens() throws { lock.withLock { tokens = nil } }
    func loadRegistration() throws -> ChatGPTRegistration? { lock.withLock { registration } }
    func saveRegistration(_ registration: ChatGPTRegistration) throws { lock.withLock { self.registration = registration } }
}

extension ChatGPTTokenSet {
    static func expiring(at date: Date) -> ChatGPTTokenSet {
        ChatGPTTokenSet(
            clientID: "oaiapp_test",
            accessToken: "access-1",
            refreshToken: "refresh-1",
            idToken: nil,
            expiresAt: date,
            scopes: ChatGPTAuthConfiguration.scopes,
            email: "dev@example.com",
            accountID: "user-1"
        )
    }
}

enum ChatGPTTestTokens {
    static func idToken(clientID: String, nonce: String, expiresIn: TimeInterval = 3_600) -> String {
        let header = encode(["alg": "RS256", "typ": "JWT"])
        let payload = encode([
            "iss": "https://auth.openai.com",
            "aud": clientID,
            "sub": "user-1",
            "email": "dev@example.com",
            "nonce": nonce,
            "exp": Date().addingTimeInterval(expiresIn).timeIntervalSince1970,
        ])
        return "\(header).\(payload).signature"
    }

    /// A Codex ID token: no nonce, and the account and plan in OpenAI's namespaced claims.
    static func codexIDToken(accountID: String, planType: String) -> String {
        let header = encode(["alg": "RS256", "typ": "JWT"])
        let payload = encode([
            "iss": "https://auth.openai.com",
            "aud": "app_EMoamEEZ73f0CkXaXp7hrann",
            "sub": "user-1",
            "exp": Date().addingTimeInterval(3_600).timeIntervalSince1970,
            "https://api.openai.com/profile": ["email": "dev@example.com"],
            "https://api.openai.com/auth": ["chatgpt_account_id": accountID, "chatgpt_plan_type": planType],
        ])
        return "\(header).\(payload).signature"
    }

    private static func encode(_ object: [String: Any]) -> String {
        (try! JSONSerialization.data(withJSONObject: object))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Holds a loopback TCP port open (without address reuse), like another app's sign-in listener.
final class OccupiedLoopbackPort {
    let port: UInt16
    private let socketDescriptor: Int32

    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EMFILE) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                Darwin.bind(descriptor, generic, length) == 0
                    && listen(descriptor, 1) == 0
                    && getsockname(descriptor, generic, &length) == 0
            }
        }
        guard bound else {
            Darwin.close(descriptor)
            throw POSIXError(.EADDRINUSE)
        }
        socketDescriptor = descriptor
        port = UInt16(bigEndian: address.sin_port)
    }

    func close() {
        Darwin.close(socketDescriptor)
    }
}

final class ChatGPTTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date { lock.withLock { date } }

    func advance(by interval: TimeInterval) {
        lock.withLock { date += interval }
    }
}

/// Answers by URL path; unknown paths return 404 so unexpected requests are visible.
actor ChatGPTStubHTTPClient: AIProviderHTTPClient {
    private var responses: [String: (status: Int, body: String)] = [:]
    private var requests: [URLRequest] = []
    private let delay: UInt64

    init(delay: UInt64 = 0) {
        self.delay = delay
    }

    func respond(to path: String, status: Int = 200, body: String) {
        responses[path] = (status, body)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        let path = request.url?.path ?? ""
        let response = responses[path] ?? (404, "{}")
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: nil)!
        return (Data(response.body.utf8), http)
    }

    func requests(path: String) -> [URLRequest] {
        requests.filter { $0.url?.path == path }
    }

    func allRequests() -> [URLRequest] {
        requests
    }
}
