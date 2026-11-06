import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WINLATOR")
                            .font(.caption.weight(.bold))
                            .tracking(3)
                            .foregroundStyle(.cyan)
                        Text("Your PC, on iPhone.")
                            .font(.largeTitle.bold())
                        Text("Connect to a Windows or Linux cloud workstation.")
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        StatusCard(title: "Windows", subtitle: "Not connected", symbol: "pc")
                        StatusCard(title: "Linux", subtitle: "Not connected", symbol: "terminal")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick launch")
                            .font(.title2.bold())
                        FeatureRow(title: "VS Code workspace", subtitle: "Remote development environment", symbol: "chevron.left.forwardslash.chevron.right")
                        FeatureRow(title: "IDA Pro workstation", subtitle: "Windows or Linux analysis desktop", symbol: "magnifyingglass")
                        FeatureRow(title: "Game streaming", subtitle: "Cloud GPU session — planned", symbol: "gamecontroller")
                    }

                    Text("Cloud connection is not configured yet. This build is the UI foundation, not a functioning remote PC.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding()
            }
            .background(Color.black)
            .navigationBarHidden(true)
        }
    }
}

private struct StatusCard: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.cyan)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .padding()
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct FeatureRow: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.cyan)
                .frame(width: 38, height: 38)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding()
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
}
