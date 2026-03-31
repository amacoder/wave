//
//  WhisperService.swift
//  Wave
//
//  OpenAI Whisper API integration
//

import Foundation

class WhisperService {
    private let baseURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    
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
        model: WhisperModel,
        language: String? = nil,
        prompt: String? = nil
    ) async throws -> String {
        
        // Read audio file
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            throw TranscriptionError(message: "Failed to read audio file: \(error.localizedDescription)")
        }
        
        // Check file size (max 25MB)
        let maxSize = 25 * 1024 * 1024
        guard audioData.count <= maxSize else {
            throw TranscriptionError(message: "Audio file too large. Maximum size is 25MB.")
        }
        
        // Create multipart form request
        let boundary = UUID().uuidString
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Build multipart body
        var body = Data()
        
        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model.rawValue)\r\n".data(using: .utf8)!)
        
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
        
        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

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
    
    // MARK: - Streaming Transcription (for future use)
    
    func transcribeStreaming(
        audioURL: URL,
        apiKey: String,
        model: WhisperModel,
        language: String? = nil,
        onPartialResult: @escaping (String) -> Void
    ) async throws -> String {
        // For now, fall back to non-streaming
        // TODO: Implement streaming when needed
        return try await transcribe(audioURL: audioURL, apiKey: apiKey, model: model, language: language)
    }
    
    // MARK: - Helpers
    
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
