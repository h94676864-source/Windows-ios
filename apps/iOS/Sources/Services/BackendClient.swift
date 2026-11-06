import Foundation

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
            return "Backend health check failed (HTTP \(code))."
        }
    }
}

struct BackendClient {
    let baseURL: URL
    var session: URLSession = .shared

    func checkHealth() async throws -> String {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme == "https" || components.scheme == "http" else {
            throw BackendConnectionError.invalidURL
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "/health" : "/\(basePath)/health"
        guard let url = components.url else { throw BackendConnectionError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendConnectionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendConnectionError.httpStatus(http.statusCode)
        }
        if let body = String(data: data, encoding: .utf8), !body.isEmpty {
            return body
        }
        return "HTTP \(http.statusCode) — backend reachable."
    }
}
