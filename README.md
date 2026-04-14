# DashType

DashType is a native macOS text expander for fast snippets, rich text templates, and optional cloud sync.

Type a short trigger like `/greet` and DashType expands it instantly anywhere you write. It is built for replies, links, signatures, notes, support macros, and formatted templates you use every day.

## Features

- Native macOS dashboard with folders and snippet management
- Rich text snippets with bold, italic, underline, links, headings, lists, subscript, and superscript
- Menu bar access for quick control without keeping a full window open
- Settings window with `Open at Login`, `Show in the Menubar`, and `Turn Off DashType`
- Import and export for snippet backups and moving between Macs
- Optional cloud sync with email/password sign in
- Local-first storage with offline editing and automatic cloud upload when the network returns

## How It Works

- Create folders to organize snippets by topic or workflow
- Add a trigger, title, and expanded text for each snippet
- Type the trigger in any app where Accessibility access is allowed
- DashType replaces the trigger with the saved snippet content

For the smoothest experience, use triggers with a prefix such as `/`, `;`, or `-`.

Examples:

- `/greet`
- `;sig`
- `-meeting`

## Rich Text

DashType stores both plain text content and rich text data, so formatting is preserved when pasting into apps that support rich text.

Supported formatting includes:

- Bold
- Italic
- Underline
- Strikethrough
- Links
- Headings
- Bullet lists
- Numbered lists
- Subscript
- Superscript

## Cloud Sync

Cloud sync is optional.

When `Sync with Cloud` is turned on:

- DashType asks you to sign in or create an account with email and password
- It performs a one-time merge between local snippets and cloud snippets
- Duplicate triggers are avoided during that first merge
- Newer snippet versions win when local and cloud copies differ
- Later changes upload from your Mac to the cloud automatically
- If you are offline, changes stay local first and upload when connectivity returns

## Settings

DashType includes a dedicated settings window with:

- `Sync with Cloud`
- `Open at Login`
- `Show in the Menubar`
- `Turn Off DashType`
- `Import Snippets`
- `Export Snippets`

If you are signed in to cloud sync, the settings window also includes a sign-out button beside the sync toggle.

## Installation

1. Download the latest `DashType.dmg` from [Releases](https://github.com/ismailhrifat/DashType/releases).
2. Open the `.dmg` file.
3. Drag `DashType.app` into your `Applications` folder.
4. If macOS says the app is damaged because it is unsigned, open Terminal and run:

```bash
sudo xattr -rd com.apple.quarantine /Applications/DashType.app
```

5. Launch DashType.
6. Grant Accessibility access when macOS prompts you.

Accessibility permission is required so DashType can detect triggers and replace text in other apps.

## Import and Export

You can back up or move snippets in two ways:

- From the Settings window with `Import Snippets` and `Export Snippets`
- From the macOS `File` menu with `Import...` and `Export...`

This is useful for backups, migration, and sharing snippet sets between Macs.

## Build From Source

Requirements:

- macOS 14 or later
- Xcode 15 or later

Steps:

1. Clone the repository.
2. Open `DashType.xcodeproj`.
3. Let Xcode resolve Swift packages.
4. Build and run the `DashType` scheme.

## Firebase Setup

Cloud sync uses Firebase Authentication and Cloud Firestore.

If you are setting up your own Firebase project:

1. Create an Apple app in Firebase using your macOS bundle identifier.
2. Enable `Email/Password` in Firebase Authentication.
3. Create a Cloud Firestore database.
4. Add `GoogleService-Info.plist` to `Config/`.
5. Ensure the app target has Keychain Sharing enabled for Firebase Auth on macOS.

## Privacy

DashType is local-first.

- Snippets are stored on your Mac by default
- Cloud sync is optional and only used when you enable it
- Rich text content is preserved during local storage and cloud sync

## Good Fit For

- Writers
- Developers
- Support teams
- Founders
- Students
- Anyone repeating the same text all day

## Feedback

If you find a bug or want to suggest an improvement, open an issue or start a discussion on GitHub.
