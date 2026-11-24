cask "asky" do
  version "0.3.8"
  sha256 "43d8c0f2d06f41e0a3800f46c3b59165a2628b9a4ccb769a933ea2b4524f74fb"

  url "https://github.com/Niall-Young/Asky/releases/download/v#{version}/Asky-#{version}-macos-arm64.dmg"
  name "Asky"
  desc "Native launcher with local search, clipboard history, and an AI assistant"
  homepage "https://github.com/Niall-Young/Asky"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Asky.app"
end
