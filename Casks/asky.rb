cask "asky" do
  version "0.3.2"
  sha256 "caa65c682f5b41256afd32776ce7f04a5eb6e1d109af18748f15b35a72121923"

  url "https://github.com/Niall-Young/Asky/releases/download/v#{version}/Asky-#{version}-macos-arm64.dmg"
  name "Asky"
  desc "Native launcher with local search, clipboard history, and an AI assistant"
  homepage "https://github.com/Niall-Young/Asky"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Asky.app"
end
