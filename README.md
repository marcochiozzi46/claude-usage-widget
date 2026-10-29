# Claude Usage Widget

A macOS desktop widget and menu bar item that show how much of your Claude plan limit you've used, and how long until it resets.

- **Small widget:** a ring with the current 5-hour session usage, the time until it resets, and your weekly usage.
- **Medium widget:** two rings, one for the 5-hour session and one for the week, each with its own countdown.
- **Menu bar:** `✳︎ 18%` at a glance, with a menu to refresh manually and to launch at login.

The ring is orange below 70%, yellow up to 90%, and red above. If the data can't be refreshed, for example because you're offline, the widget keeps the last value and shows when it was last updated.

The limit is shared across claude.ai, the Claude apps and Claude Code, so the number is the same one you see in Claude Code's `/usage`.

> **Unofficial.** This project is not affiliated with Anthropic. It uses an undocumented endpoint (`api.anthropic.com/api/oauth/usage`) that may change or stop working at any time.

## How it works

The app reuses the login that [Claude Code](https://docs.claude.com/en/docs/claude-code) stores in your macOS Keychain (item `Claude Code-credentials`). It reads the usage every 5 minutes and shares it with the widget through an App Group container.

Claude Code's access token is short-lived. When it is about to expire, the app refreshes it and writes the new token back to the Keychain, in the same format and with the same `security` command Claude Code uses, so Claude Code keeps working. In the rare case that both refresh at the same moment, Claude Code may ask you to run `/login` again.

Your credentials never leave your Mac except to talk to Anthropic's own servers.

## Requirements

- macOS 14 or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Claude Code installed and logged in with a Claude subscription
- An Apple ID added in Xcode → Settings → Accounts (a free account is enough)

## Build

1. Create `Config/Local.xcconfig` with your signing settings:

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   BUNDLE_ID_PREFIX = com.yourname
   ```

   Your Team ID is shown in Xcode → Settings → Accounts, or in Keychain Access as the "OU" of your "Apple Development" certificate.

2. Generate the project and build:

   ```sh
   xcodegen generate
   xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -configuration Release \
     -derivedDataPath build -allowProvisioningUpdates build
   cp -R build/Build/Products/Release/ClaudeUsage.app /Applications/
   open /Applications/ClaudeUsage.app
   ```

3. Right-click the desktop → **Edit Widgets** and add **Claude Usage**.

The first time the app reads the Keychain, macOS may ask for permission: choose **Always Allow**.

## License

MIT
