# Restore chat header gradient

Restored the original AgentHeaderBackdrop implementation and header attachment from before 97e0ee4. Preserved existing toolbar glass and unrelated workspace edits.

## Verification

- xcodegen generate: passed.
- KulaCore swift test with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer: exit 0.
- xcodebuild Debug using the README command and build/DerivedData: BUILD SUCCEEDED.
- Relaunched the freshly built Debug with --show-agent. Actual window appearance was not visually inspected.

README: unchanged - restores previous styling without usage or command changes.
AGENTS.md: unchanged - no durable instruction changes.
Build output uses existing ignored build/ and Asky.xcodeproj/ paths.
