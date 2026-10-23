import SwiftUI
import WebKit

struct MuscleMapView: View {
    @Binding var selection: [Muscle]
    @State private var back = false
    var body: some View {
        VStack {
            Picker("Body view", selection: $back) { Text("Front").tag(false); Text("Back").tag(true) }.pickerStyle(.segmented).padding(.horizontal, FitTheme.pageInset)
            MuscleSVG(back: back, selected: selection) { muscle in
                if selection.contains(muscle) { selection.removeAll { $0 == muscle } } else { selection.append(muscle) }
            }
            ScrollView(.horizontal) {
                HStack {
                    ForEach(Muscle.allCases) { muscle in
                        Button {
                            if selection.contains(muscle) { selection.removeAll { $0 == muscle } } else { selection.append(muscle) }
                        } label: { Label(muscle.title, systemImage: selection.contains(muscle) ? "checkmark.circle.fill" : "circle") }
                            .buttonStyle(.bordered).accessibilityIdentifier("muscle-" + muscle.rawValue)
                            .accessibilityAddTraits(selection.contains(muscle) ? .isSelected : [])
                    }
                }.padding(.horizontal, FitTheme.pageInset)
            }
            Text(selection.isEmpty ? "Tap a muscle to select it." : "Selected: " + selection.map(\.title).joined(separator: ", "))
                .font(FitTheme.body(16)).padding(.horizontal, FitTheme.pageInset).padding(.vertical, FitTheme.cardInset).accessibilityIdentifier("selectedMuscles")
        }.navigationTitle("Muscle map")
    }
}
private struct MuscleSVG: UIViewRepresentable {
    let back: Bool
    let selected: [Muscle]
    let select: (Muscle) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(select: select) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "muscle")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false; view.backgroundColor = .clear; view.scrollView.isScrollEnabled = false
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.select = select
        let key = "\(back)-\(selected.map(\.rawValue).sorted().joined(separator: ","))"
        guard key != context.coordinator.loaded else { return }; context.coordinator.loaded = key
        guard let url = Bundle.main.url(forResource: back ? "anatomy-back" : "anatomy-front", withExtension: "svg"), let svg = try? String(contentsOf: url, encoding: .utf8) else {
            view.loadHTMLString("<p>Muscle illustration unavailable. Use the named muscle toggles in the editor.</p>", baseURL: nil); return
        }
        let identifiers = selected.map { "'\($0.rawValue)'" }.joined(separator: ",")
        let html = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{margin:0;background:transparent;color:white}svg{width:100%;height:100vh}.muscle.selected{fill:#ff4504!important;stroke:white!important;stroke-width:3!important}</style></head><body>\(svg)<script>
        const selected=new Set([\(identifiers)]);
        document.querySelectorAll('[data-muscle]').forEach(el=>{
        const id=el.dataset.muscle;el.classList.toggle('selected',selected.has(id));el.setAttribute('role','button');el.setAttribute('tabindex','0');el.setAttribute('aria-pressed',selected.has(id)?'true':'false');
        const activate=()=>window.webkit.messageHandlers.muscle.postMessage(id);
        el.addEventListener('click',activate);el.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();activate();}});
        });</script></body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { view.configuration.userContentController.removeScriptMessageHandler(forName: "muscle") }
    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler {
        var loaded = ""
        var select: (Muscle) -> Void
        init(select: @escaping (Muscle) -> Void) { self.select = select }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let raw = message.body as? String, let muscle = Muscle(rawValue: raw) else { return }
            select(muscle)
        }
    }
}
