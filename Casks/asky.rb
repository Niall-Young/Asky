cask "asky" do
  version "0.3.4"
  sha256 "31415b1e1da8db23cc1009e3c10f10bfcfe40c7ec6c5f154319a9ae2aa4c4345"

  url "https://github.com/Niall-Young/Asky/releases/download/v#{version}/Asky-#{version}-macos-arm64.dmg"
  name "Asky"
  desc "Native launcher with local search, clipboard history, and an AI assistant"
  homepage "https://github.com/Niall-Young/Asky"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Asky.app"
end
