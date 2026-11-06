import Foundation

enum WorkspaceOperatingSystem: String, Codable, CaseIterable, Identifiable {
    case windows
    case linux

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .windows ? "pc" : "terminal" }
}

struct RemoteWorkspace: Codable, Identifiable {
    let id: String
    let name: String
    let operatingSystem: WorkspaceOperatingSystem
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, name, status
        case operatingSystem = "operating_system"
    }
}

struct CreateWorkspaceRequest: Encodable {
    let name: String
    let operatingSystem: WorkspaceOperatingSystem

    enum CodingKeys: String, CodingKey {
        case name
        case operatingSystem = "operating_system"
    }
}

enum BackendConnectionError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid HTTPS backend URL."
        case .invalidResponse:
            return "The backend returned an invalid response."
        case .httpStatus(let code):
            return "Backend request failed (HTTP \(code))."
        }
    }
}

struct BackendClient {
    let baseURL: URL
    var session: URLSession = .shared

    func checkHealth() async throws -> String {
        let (data, response) = try await send(path: "/health", method: "GET")
        if let body = String(data: data, encoding: .utf8), !body.isEmpty {
            return body
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        return "HTTP \(status) — backend reachable."
    }

    func listWorkspaces() async throws -> [RemoteWorkspace] {
        let (data, _) = try await send(path: "/api/v1/workspaces", method: "GET")
        return try JSONDecoder().decode([RemoteWorkspace].self, from: data)
    }

    func createWorkspace(name: String, operatingSystem: WorkspaceOperatingSystem) async throws -> RemoteWorkspace {
        let payload = CreateWorkspaceRequest(name: name, operatingSystem: operatingSystem)
        let body = try JSONEncoder().encode(payload)
        let (data, _) = try await send(path: "/api/v1/workspaces", method: "POST", body: body)
        return try JSONDecoder().decode(RemoteWorkspace.self, from: data)
    }

    func stopWorkspace(id: String) async throws {
        let safeID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        _ = try await send(path: "/api/v1/workspaces/\(safeID)", method: "DELETE")
    }

    private func send(path: String, method: String, body: Data? = nil) async throws -> (Data, URLResponse) {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https" || components.scheme?.lowercased() == "http",
              components.host != nil else {
            throw BackendConnectionError.invalidURL
        }
        let prefix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([prefix, path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
            .filter { !$0.isEmpty }.joined(separator: "/"))
        guard let url = components.url else { throw BackendConnectionError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendConnectionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendConnectionError.httpStatus(http.statusCode)
        }
        return (data, response)
    }
}
