// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import WebKit

struct RepositoryReadmeWebView: NSViewRepresentable {
    let content: String
    var directory: URL? = nil
    var baseURL: URL? = nil
    var textScale: Double = 1
    var compact: Bool = false
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        // Isolated app script measures layout; README scripts remain disabled.
        configuration.userContentController.add(context.coordinator, contentWorld: .defaultClient, name: "readmeHeight")
        configuration.userContentController.addUserScript(WKUserScript(source: """
            let pending = false;
            function reportHeight() {
                if (pending) return;
                pending = true;
                requestAnimationFrame(() => {
                    pending = false;
                    window.webkit.messageHandlers.readmeHeight.postMessage(Math.ceil(document.body.getBoundingClientRect().height));
                });
            }
            new ResizeObserver(reportHeight).observe(document.body);
            reportHeight();
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        configuration.setURLSchemeHandler(context.coordinator, forURLScheme: "commitplus-readme")
        let view = RepositoryReadmeContentView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onHeightChange = { height in
            if abs(contentHeight - height) > 1 { contentHeight = height }
        }
        let resolvedDirectory = directory?.resolvingSymlinksInPath().standardizedFileURL
        guard coordinator.content != content || coordinator.directory != resolvedDirectory || coordinator.baseURL != baseURL || coordinator.textScale != textScale || coordinator.compact != compact else { return }
        coordinator.content = content
        coordinator.directory = resolvedDirectory
        coordinator.baseURL = baseURL
        coordinator.textScale = textScale
        coordinator.compact = compact
        view.loadHTMLString(RepositoryReadmeHTML.render(content, textScale: textScale, compact: compact), baseURL: baseURL ?? URL(string: "commitplus-readme://repository/"))
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        (view as? RepositoryReadmeContentView)?.stopForwardingScroll()
        view.stopLoading()
        view.navigationDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "readmeHeight", contentWorld: .defaultClient)
        coordinator.cancelRequests()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKURLSchemeHandler, WKScriptMessageHandler {
        var content: String?
        var directory: URL?
        var baseURL: URL?
        var textScale: Double = 1
        var compact = false
        var onHeightChange: ((CGFloat) -> Void)?
        private var requests: [ObjectIdentifier: Task<Void, Never>] = [:]

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.ceil(document.body.getBoundingClientRect().height)", in: nil, in: .defaultClient) { [weak self] result in
                guard case .success(let value) = result, let height = value as? Double, height.isFinite, height > 0 else { return }
                self?.onHeightChange?(ceil(height))
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let height = message.body as? Double, height.isFinite, height > 0 else { return }
            onHeightChange?(max(1, ceil(height)))
        }

        func cancelRequests() {
            requests.values.forEach { $0.cancel() }
            requests.removeAll()
        }

        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            guard let directory, let url = urlSchemeTask.request.url, url.host == "repository" else {
                urlSchemeTask.didFailWithError(URLError(.badURL)); return
            }
            let file = directory.appendingPathComponent(url.path).resolvingSymlinksInPath().standardizedFileURL
            guard file.path.hasPrefix(directory.path + "/") else {
                urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile)); return
            }
            let key = ObjectIdentifier(urlSchemeTask)
            requests[key] = Task { @MainActor in
                defer { requests[key] = nil }
                do {
                    let data = try await Task.detached(priority: .utility) {
                        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 20 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
                        return try Data(contentsOf: file)
                    }.value
                    guard !Task.isCancelled else { return }
                    let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                } catch {
                    if !Task.isCancelled { urlSchemeTask.didFailWithError(error) }
                }
            }
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
            requests.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated else {
                let url = navigationAction.request.url
                // loadHTMLString uses its base URL for the initial navigation.
                // PR content has an HTTPS base URL instead of the README scheme.
                let isDocument = url?.absoluteString == "about:blank" ||
                    (baseURL != nil && url == baseURL) ||
                    (url?.scheme == "commitplus-readme" && url?.host == "repository" && url?.path == "/")
                decisionHandler(isDocument && navigationAction.targetFrame?.isMainFrame == true ? .allow : .cancel)
                return
            }
            if let url = navigationAction.request.url {
                if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
                else if url.scheme == "commitplus-readme", url.fragment != nil { decisionHandler(.allow); return }
            }
            decisionHandler(.cancel)
        }
    }
}
