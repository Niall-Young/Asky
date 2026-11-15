cask "asky" do
  version "0.3.0"
  sha256 "06d9bacdd5b8a819edb6adeee7b821236ab4416f2d63c598da4c62d8de2883e1"

  url "https://github.com/Niall-Young/Asky/releases/download/v#{version}/Asky-#{version}-macos-arm64.dmg"
  name "Asky"
  desc "Native launcher with local search, clipboard history, and an AI assistant"
  homepage "https://github.com/Niall-Young/Asky"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Asky.app"
end
