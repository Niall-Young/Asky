import Foundation

/// Public OpenAI-compatible endpoints. Keep IDs stable because settings persist them.
struct ModelProviderPreset: Identifiable {
    let id: String
    let name: String
    let baseURL: String
    let models: [String]
    let keyURL: URL

    static let all: [Self] = [
        .init(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com",
              models: ["deepseek-flash", "deepseek-v4-pro"], keyURL: URL(string: "https://platform.deepseek.com/api_keys")!),
        .init(id: "minimax", name: "MiniMax", baseURL: "https://api.minimax.cn/v1",
              models: ["MiniMax-M3.1-Flash", "MiniMax-M3"], keyURL: URL(string: "https://platform.minimaxi.com")!),
        .init(id: "glm", name: "GLM（智谱）", baseURL: "https://open.bigmodel.cn/api/paas/v4",
              models: ["glm-5.3-flash", "glm-5.3-flashx", "glm-5.3", "glm-5.4"],
              keyURL: URL(string: "https://bigmodel.cn/usercenter/proj-mgmt/apikeys")!),
        .init(id: "kimi", name: "Kimi", baseURL: "https://api.moonshot.ai/v1",
              models: ["kimi-k3.1-pro", "kimi-k3.1-pro-highspeed", "kimi-k3"], keyURL: URL(string: "https://platform.kimi.ai")!),
        .init(id: "qwen", name: "Qwen（通义千问 · 北京）", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
              models: ["qwen3.8-flash", "qwen3.7-plus", "qwen4-max", "qwen3.8-max", "qwen-plus"],
              keyURL: URL(string: "https://bailian.console.aliyun.com")!),
        .init(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1",
              models: ["gpt-6-luna", "gpt-5.6-terra", "gpt-5.6-sol", "gpt-5.4"],
              keyURL: URL(string: "https://platform.openai.com/api-keys")!),
    ]

    static func find(_ id: String) -> Self? { all.first { $0.id == id } }
    static func normalizedURL(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }
}

/// A draft never overwrites saved settings until Save. Unknown/edited legacy presets stay custom.
struct ModelConfigurationDraft {
    var provider: String
    var baseURL: String
    var model: String
    private var custom: (baseURL: String, model: String)?

    init(provider: String, baseURL: String?, model: String?) {
        if let baseURL, let model {
            self.baseURL = baseURL
            self.model = model
            let preset = ModelProviderPreset.find(provider)
            self.provider = preset.map {
                ModelProviderPreset.normalizedURL($0.baseURL) == ModelProviderPreset.normalizedURL(baseURL)
                    && $0.models.contains(model) ? provider : "custom"
            } ?? "custom"
            custom = self.provider == "custom" ? (baseURL, model) : nil
        } else {
            let preset = ModelProviderPreset.all[0]
            self.provider = preset.id
            self.baseURL = preset.baseURL
            self.model = preset.models[0]
        }
    }

    mutating func select(_ id: String) {
        guard id != provider else { return }
        if provider == "custom" { custom = (baseURL, model) }
        provider = id
        if let preset = ModelProviderPreset.find(id) {
            baseURL = preset.baseURL
            model = preset.models[0]
        } else if let custom {
            baseURL = custom.baseURL
            model = custom.model
        }
        // Without an earlier custom draft, keep the current preset as a starting point.
    }

    func canReuseCredential(savedBaseURL: String?) -> Bool {
        guard let savedBaseURL else { return false }
        return ModelProviderPreset.normalizedURL(savedBaseURL) == ModelProviderPreset.normalizedURL(baseURL)
    }
}
