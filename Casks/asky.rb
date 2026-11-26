cask "asky" do
  version "0.3.11"
  sha256 "f6a7e84b8935b0a165894c337836232ecff97a1ac0bdfc5068769ef269457210"

  url "https://github.com/Niall-Young/Asky/releases/download/v#{version}/Asky-#{version}-macos-arm64.dmg"
  name "Asky"
  desc "Native launcher with local search, clipboard history, and an AI assistant"
  homepage "https://github.com/Niall-Young/Asky"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Asky.app"
end
