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
        fresh.select("glm")
        assert(fresh.model == "glm-5.3-flash")
        assert(ModelProviderPreset.find("glm")?.models == ["glm-5.3-flash", "glm-5.3-flashx", "glm-5.3", "glm-5.4"])
        fresh.select("minimax")
        let base = fresh.baseURL
        fresh.select("custom")
        assert(fresh.baseURL == base)
        print("Provider presets, legacy preservation, custom draft restoration and credential boundaries passed")
    }
}
