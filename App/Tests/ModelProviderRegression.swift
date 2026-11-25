import Foundation

@main
enum ModelProviderRegression {
    static func main() {
        var fresh = ModelConfigurationDraft(provider: "custom", baseURL: nil, model: nil)
        assert(fresh.provider == "deepseek" && !fresh.model.isEmpty)
        for preset in ModelProviderPreset.all {
            fresh.select(preset.id)
            assert(fresh.baseURL == preset.baseURL && fresh.model == preset.models[0])
            assert(URL(string: fresh.baseURL)!.appending(path: "chat/completions").absoluteString.hasSuffix("/chat/completions"))
            assert(fresh.canReuseCredential(savedBaseURL: preset.baseURL + "/"))
            assert(!fresh.canReuseCredential(savedBaseURL: "https://proxy.example/v1"))
            let restored = ModelConfigurationDraft(provider: preset.id, baseURL: preset.baseURL + "/", model: preset.models.last!)
            assert(restored.provider == preset.id && restored.model == preset.models.last!)
        }
        var legacy = ModelConfigurationDraft(provider: "deepseek", baseURL: "https://proxy.example/v1", model: "my-model")
        assert(legacy.provider == "custom")
        legacy.select("kimi")
        legacy.select("custom")
        assert(legacy.baseURL == "https://proxy.example/v1" && legacy.model == "my-model")
        let oldModel = ModelConfigurationDraft(provider: "deepseek", baseURL: "https://api.deepseek.com", model: "deepseek-chat")
        assert(oldModel.provider == "custom" && oldModel.model == "deepseek-chat")
        let glmLegacy = ModelConfigurationDraft(provider: "glm", baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-5.3")
        assert(glmLegacy.provider == "glm" && glmLegacy.model == "glm-5.3")
        let qwenLegacy = ModelConfigurationDraft(provider: "qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus")
        assert(qwenLegacy.provider == "qwen" && qwenLegacy.model == "qwen-plus")
        let retiredMiniMax = ModelConfigurationDraft(provider: "minimax", baseURL: "https://api.minimax.cn/v1", model: "MiniMax-M2.7")
        assert(retiredMiniMax.provider == "custom" && retiredMiniMax.model == "MiniMax-M2.7")
        let retiredOpenAI = ModelConfigurationDraft(provider: "openai", baseURL: "https://api.openai.com/v1", model: "gpt-4.1")
        assert(retiredOpenAI.provider == "custom" && retiredOpenAI.model == "gpt-4.1")
        assert(ModelProviderPreset.find("minimax")?.models == ["MiniMax-M3.1-Flash", "MiniMax-M3"])
        assert(ModelProviderPreset.find("glm")?.models == ["glm-5.3-flash", "glm-5.3-flashx", "glm-5.3", "glm-5.4"])
        assert(ModelProviderPreset.find("kimi")?.models == ["kimi-k3.1-pro", "kimi-k3.1-pro-highspeed", "kimi-k3"])
        assert(ModelProviderPreset.find("qwen")?.models == ["qwen3.8-flash", "qwen3.7-plus", "qwen4-max", "qwen3.8-max", "qwen-plus"])
        assert(ModelProviderPreset.find("openai")?.models == ["gpt-6-luna", "gpt-5.6-terra", "gpt-5.6-sol", "gpt-5.4"])
        fresh.select("glm")
        assert(fresh.model == "glm-5.3-flash")
        fresh.select("minimax")
        assert(fresh.model == "MiniMax-M3.1-Flash")
        let base = fresh.baseURL
        fresh.select("custom")
        assert(fresh.baseURL == base)
        print("Provider presets, legacy preservation, custom draft restoration and credential boundaries passed")
    }
}
