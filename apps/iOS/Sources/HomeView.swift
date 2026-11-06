import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WINLATOR")
                            .font(.caption.weight(.bold))
                            .tracking(3)
                            .foregroundStyle(.cyan)
                        Text("Your PC. In your pocket.")
                            .font(.largeTitle.bold())
                        Text("A Windows-style desktop on iPhone, with cloud workstations for development and analysis.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        WindowsDesktopView()
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: [Color(red: 0.03, green: 0.22, blue: 0.42), Color(red: 0.02, green: 0.07, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Circle().fill(.cyan.opacity(0.18)).frame(width: 190).blur(radius: 8).offset(x: 190, y: -65)
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: "display").font(.system(size: 30, weight: .medium))
                                Text("Open Windows desktop").font(.title2.bold())
                                Text("Start menu • Taskbar • Desktop apps").font(.caption).foregroundStyle(.white.opacity(0.75))
                                HStack {
                                    Text("LAUNCH DESKTOP").font(.caption.weight(.bold)).tracking(1)
                                    Image(systemName: "arrow.up.right")
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(.cyan, in: Capsule()).foregroundStyle(.black)
                            }
                            .padding(22)
                        }
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        HomeStatusCard(title: "Windows", subtitle: "Desktop preview", symbol: "pc")
                        HomeStatusCard(title: "Linux", subtitle: "Cloud workspace", symbol: "terminal")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Workstation tools").font(.title2.bold())
                        HomeFeatureRow(title: "VS Code", subtitle: "Remote development workspace", symbol: "chevron.left.forwardslash.chevron.right")
                        HomeFeatureRow(title: "IDA Pro", subtitle: "Reverse-engineering workstation", symbol: "magnifyingglass")
                        HomeFeatureRow(title: "Game streaming", subtitle: "GPU cloud session — later phase", symbol: "gamecontroller")
                    }

                    Text("Desktop preview runs inside the app. A live Windows PC/RDP stream needs a deployed Windows host and remote-session gateway; those services are not part of the iOS app build.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding()
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Winlator")
        }
    }
}

private struct HomeStatusCard: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.cyan)
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding()
        .background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct HomeFeatureRow: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.cyan)
                .frame(width: 42, height: 42)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}
