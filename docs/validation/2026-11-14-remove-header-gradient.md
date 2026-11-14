# Remove chat header gradient

Removed AgentHeaderBackdrop and its header background attachment, including its opaque accessibility fallback. Preserved toolbar layout, native Clear glass, opacity and interactions.

## Executed checks

- xcodegen generate: passed.
- DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test (Packages/KulaCore): exit 0.
- DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Asky.xcodeproj -scheme Asky -configuration Debug -derivedDataPath build/DerivedData build: BUILD SUCCEEDED.
- Compared source with the pre-task snapshot: only removed header backdrop attachment and private view.

## Limits and documentation gates

The running application was not restarted; actual window appearance was not visually checked. Existing workspace edits were preserved.

README: unchanged - a small visual adjustment with no usage or command changes.
AGENTS.md: unchanged - no architectural, workflow or durable instruction changes.
