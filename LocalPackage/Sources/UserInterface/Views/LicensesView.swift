import Model
import SwiftUI

struct LicensesView: View {
    var store: Licenses
    @State private var licensesText = ""

    var body: some View {
        ScrollView {
            Text(licensesText.isEmpty ? "Third-party license information is unavailable." : licensesText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(Text("licenses", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.send(.task(String(describing: Self.self)))
            licensesText = loadLicensesText()
        }
    }

    private func loadLicensesText() -> String {
        guard let url = Bundle.module.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
