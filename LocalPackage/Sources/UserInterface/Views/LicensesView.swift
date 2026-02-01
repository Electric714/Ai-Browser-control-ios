import Model
import SwiftUI

struct LicensesView: View {
    var store: Licenses
    @State private var licensesText = ""

    var body: some View {
        ScrollView {
            Text(licensesText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
            .navigationTitle(Text("licenses", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await store.send(.task(String(describing: Self.self)))
                licensesText = loadLicensesText()
            }
    }

    private func loadLicensesText() -> String {
        guard let url = Bundle.module.url(forResource: "Licenses", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("Missing Licenses.md in UserInterface resources.")
            return "Third-party licenses are currently unavailable."
        }
        return text
    }
}
