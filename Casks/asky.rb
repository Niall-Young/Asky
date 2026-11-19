cask "asky" do
  version "0.3.5"
  sha256 "92aef18c09d56fcc2d4858cc5d51f8083ff91ebed1a43adf9c97ecd22952f4b7"

  url "https://github.com/Niall-Young/Asky/releases/download/v#{version}/Asky-#{version}-macos-arm64.dmg"
  name "Asky"
  desc "Native launcher with local search, clipboard history, and an AI assistant"
  homepage "https://github.com/Niall-Young/Asky"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Asky.app"
end
