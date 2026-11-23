cask "asky" do
  version "0.3.7"
  sha256 "0641cfc5a69e8b0c58f1eaff1e5f348bc83fcf59ff7ceac8d2745ece83cad9fa"

  url "https://github.com/Niall-Young/Asky/releases/download/v#{version}/Asky-#{version}-macos-arm64.dmg"
  name "Asky"
  desc "Native launcher with local search, clipboard history, and an AI assistant"
  homepage "https://github.com/Niall-Young/Asky"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Asky.app"
end
