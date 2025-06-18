# Clonner

<img width="1266" alt="Screenshot 2025-06-18 at 23 27 43" src="https://github.com/user-attachments/assets/8b02e807-5244-4262-ad42-9f325b824461" />

Clonner is a macOS application for convenient management and cloning of Git repositories. The app allows you to create profiles for different repository types and easily clone or update them.

## Features

- Create profiles for different repository types (GitHub, GitLab, etc.)
- Choose a folder for cloning repositories
- Clone and update repositories
- View operation log
- User-friendly interface

## Requirements

- macOS 14.0 or newer
- Xcode 15.0 or newer (for building from source)

## Installation

1. Download the latest version of the app from the [Releases](https://github.com/yourusername/clonner/releases) section
2. Open the `clonner.dmg` file
3. Drag the Clonner app to the Applications folder
4. On first launch, macOS may show a security warning. In this case:
   - Open System Settings
   - Go to Security & Privacy
   - Click "Open Anyway" for the Clonner app

### Manual Build and Install (Terminal)

If you want to build and install the app manually from source, follow these steps:

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/clonner.git
   cd clonner
   ```
2. Build the app using Xcode command line tools:
   ```bash
   xcodebuild -scheme clonner -configuration Release -derivedDataPath build
   ```
3. Install the app to the Applications folder:
   ```bash
   cp -R build/Build/Products/Release/clonner.app /Applications/
   ```
4. (Optional) Remove build artifacts if you no longer need them:
   ```bash
   rm -rf build
   ```
5. Launch Clonner from the Applications folder as a regular macOS app.

## Building from Source

1. Clone the repository:
```bash
git clone https://github.com/yourusername/clonner.git
```

2. Open the project in Xcode:
```bash
cd clonner
open clonner.xcodeproj
```

3. Build (⌘B) or run (⌘R) the project

## Usage

1. Launch the Clonner app
2. Click "Choose Folder" to select the directory where repositories will be cloned
3. Create a new profile by clicking the "+" button
4. Fill in the profile information (type, name, etc.)
5. Use the actions menu (three dots) to clone or update repositories

## License

MIT License. See the [LICENSE](LICENSE) file for details. 
