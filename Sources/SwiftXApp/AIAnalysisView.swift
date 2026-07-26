// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// AI image analysis window (C# AIForm). The provider settings live inline;
// they persist to ApplicationConfig so hotkey and pipeline runs reuse them.

import AppKit
import SharedKit
import SwiftUI
import ToolsKit

extension ToolWindows {
    /// Hotkey/menu entry: select a region first, like C# AutoStartRegion.
    static func runAIFromRegion() {
        Task {
            guard let image = await captureRegionImage() else { return }
            showAIAnalysis(for: image)
        }
    }

    static func showAIAnalysis(for image: CGImage) {
        present(title: "AI Image Analysis", resizable: true, content: AIAnalysisView(image: image))
    }
}

private struct AIAnalysisView: View {
    let image: CGImage

    @State private var config = ApplicationConfig.load()
    @State private var response = ""
    @State private var isAnalyzing = false
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(image, scale: 2, label: Text("Image to analyze"))
                    .resizable().scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading) {
                    TextField("Prompt", text: $config.aiPrompt, axis: .vertical)
                        .lineLimit(2...4)
                    HStack {
                        Button(isAnalyzing ? "Analyzing…" : "Analyze") { analyze() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(isAnalyzing)
                        if isAnalyzing { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("Provider…") { showSettings.toggle() }
                            .popover(isPresented: $showSettings) { settingsForm }
                    }
                }
            }
            TextEditor(text: $response)
                .font(.body)
                .frame(minWidth: 460, minHeight: 180)
            HStack {
                Spacer()
                Button("Copy Response") { ToolWindows.copyToClipboard(response) }
                    .disabled(response.isEmpty)
            }
        }
        .padding()
    }

    private var settingsForm: some View {
        Form {
            TextField("Base URL", text: $config.aiBaseURL)
                .help("OpenAI: https://api.openai.com/v1 — OpenRouter: https://openrouter.ai/api/v1 — Gemini: https://generativelanguage.googleapis.com/v1beta/openai")
            SecureField("API key", text: $config.aiAPIKey)
            TextField("Model", text: $config.aiModel)
        }
        .frame(width: 380)
        .padding()
    }

    private func analyze() {
        try? config.save()
        isAnalyzing = true
        response = ""
        let (image, prompt) = (image, config.aiPrompt)
        let clientConfig = AIConfiguration(baseURL: config.aiBaseURL,
                                           apiKey: config.aiAPIKey,
                                           model: config.aiModel)
        Task {
            do {
                response = try await AIClient.analyze(image: image, prompt: prompt, config: clientConfig)
            } catch {
                response = error.localizedDescription
            }
            isAnalyzing = false
        }
    }
}
