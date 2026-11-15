cask "asky" do
  version "0.3.1"
  sha256 "f381a9ee2991070df787ee735029e64b4b61d9b4554f44891d886889f3232d16"

  url "https://github.com/Niall-Young/Asky/releases/download/v#{version}/Asky-#{version}-macos-arm64.dmg"
  name "Asky"
  desc "Native launcher with local search, clipboard history, and an AI assistant"
  homepage "https://github.com/Niall-Young/Asky"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Asky.app"
end
