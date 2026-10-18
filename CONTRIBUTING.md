# Contributing to RayBanClaude

Thanks for your interest in contributing to RayBanClaude! This guide will help you get started.

## Getting Started

1. **Fork** the repository on GitHub
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/YOUR-USERNAME/raybanclaude.git
   cd raybanclaude/RayBanClaude
   ```
3. **Run the setup** to install dependencies:
   ```bash
   ./setup.sh
   ```
4. **Create a branch** for your changes:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Project Structure

```
RayBanClaude/
├── server/           # Node.js gateway server
│   ├── src/          # TypeScript source
│   ├── skills/       # Built-in SKILL.md files
│   └── .env          # API keys (never commit this)
├── ios/              # Swift iOS app
│   ├── RayBanClaude/ # App source code
│   └── project.yml   # XcodeGen project definition
└── setup.sh          # Interactive installer
```

## Development Workflow

### Gateway Server

```bash
cd server
npm install
npm run build    # Compile TypeScript
npm start        # Start the server
```

The server auto-discovers MCP servers from your Claude Desktop config and skills from `SKILL.md` files.

### iOS App

```bash
cd ios
xcodegen generate    # Regenerate Xcode project after changing project.yml
open RayBanClaude.xcodeproj
# Build with ⌘R (must use physical iPhone, not Simulator)
```

## What to Contribute

### Good First Issues

- Add new built-in skills to `server/skills/`
- Improve the system prompt for better vision analysis
- Add new ElevenLabs voice options
- UI/UX improvements to the iOS app
- Documentation improvements

### Feature Ideas

- Android app
- Additional TTS providers (OpenAI, Google)
- WebRTC streaming for lower latency
- Multi-language speech recognition
- Photo capture mode (high-res snapshots for Claude)
- Widget for quick access

### Adding a Skill

1. Create a directory in `server/skills/your-skill-name/`
2. Add a `SKILL.md` file:
   ```markdown
   ---
   description: What this skill does
   trigger: keywords that activate it
   ---

   # Your Skill Name

   Instructions for Claude when this skill is activated...
   ```
3. Restart the server or call `POST /skills/reload`
4. The skill appears in Claude's system prompt automatically

## Pull Request Process

1. **Test your changes** — make sure the server builds cleanly (`npm run build`) and the iOS app compiles
2. **Update documentation** if you changed behavior or added features
3. **Keep commits focused** — one logical change per commit
4. **Write clear commit messages** describing what and why
5. **Open a PR** against the `main` branch with:
   - A clear title describing the change
   - A description of what was changed and why
   - Screenshots if you changed the UI

## Code Style

### TypeScript (Server)

- Use ES module imports (`import/export`)
- Prefer `const` over `let`
- Use TypeScript types — avoid `any` where possible
- Console output should use the `c` theme from `console-theme.ts`

### Swift (iOS)

- Follow Swift naming conventions (camelCase for variables, PascalCase for types)
- Use `@Published` for observable state
- Keep views small — extract subviews when they get long
- Use the `FrameSource` protocol for new camera sources

## Reporting Issues

- Use GitHub Issues for bug reports and feature requests
- Include your macOS version, Xcode version, and Node.js version
- For crashes, include the Xcode console output
- For server issues, include the terminal output

## Security

- **Never commit API keys** — they belong in `.env` (git-ignored)
- **Never commit** `node_modules/`, `DerivedData/`, or `.xcuserstate`
- Report security vulnerabilities privately via GitHub

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Questions? Open an issue or reach out to [@mrdulasolutions](https://github.com/mrdulasolutions).
