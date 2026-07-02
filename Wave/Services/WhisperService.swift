//
//  WhisperService.swift
//  Wave
//
//  OpenAI Whisper API integration
//

import Foundation

class WhisperService {
    /// 15s per-request timeout instead of the 60s default, so a dead network
    /// fails fast instead of leaving the user staring at the spinner.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()


    struct TranscriptionError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    
    struct APIErrorResponse: Codable {
        struct Error: Codable {
            let message: String
            let type: String?
            let code: String?
        }
        let error: Error
    }
    
    struct TranscriptionResponse: Codable {
        let text: String
    }
    
    // MARK: - Transcription
    
    func transcribe(
        audioURL: URL,
        apiKey: String,
        model: String,
        endpoint: URL,
        language: String? = nil,
        prompt: String? = nil
    ) async throws -> String {

        // Check file size (max 25MB) BEFORE loading the file into memory
        let maxSize = 25 * 1024 * 1024
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
        guard fileSize <= maxSize else {
            throw TranscriptionError(message: "Audio file too large. Maximum size is 25MB.")
        }

        // Read audio file
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            throw TranscriptionError(message: "Failed to read audio file: \(error.localizedDescription)")
        }
        
        // Create multipart form request
        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Build multipart body
        var body = Data()
        
        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)
        
        // Language field (optional)
        if let language = language {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(language)\r\n".data(using: .utf8)!)
        }
        
        // Prompt field (optional) - helps with context
        if let prompt = prompt {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(prompt)\r\n".data(using: .utf8)!)
        }
        
        // Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("json\r\n".data(using: .utf8)!)
        
        // Audio file
        let filename = audioURL.lastPathComponent
        let mimeType = mimeTypeForPath(filename)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body

        // Make request, with one retry on network failure or 5xx
        let (data, response) = try await sendWithRetry(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError(message: "Invalid response from server")
        }

        // Handle errors
        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw TranscriptionError(message: errorResponse.error.message)
            }
            throw TranscriptionError(message: "API request failed with status \(httpResponse.statusCode)")
        }

        // Parse response
        let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return transcriptionResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Helpers

    /// One retry on transport errors and 5xx responses; 4xx fails immediately.
    private func sendWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (500...599).contains(http.statusCode) {
                return try await session.data(for: request)
            }
            return (data, response)
        } catch {
            // Don't retry a deliberate cancellation (Escape / watchdog)
            if Task.isCancelled { throw error }
            return try await session.data(for: request)
        }
    }
    
    private func mimeTypeForPath(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "m4a": return "audio/m4a"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "webm": return "audio/webm"
        case "mp4": return "audio/mp4"
        case "ogg": return "audio/ogg"
        case "flac": return "audio/flac"
        default: return "audio/m4a"
        }
    }
}
