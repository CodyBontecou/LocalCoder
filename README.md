# LocalCoder

A native iOS and macOS coding assistant that runs entirely on-device using Apple's MLX framework. Chat with local LLMs to read, write, and edit code — no cloud, no API keys, no data leaving your device.

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS-blue)
![Swift](https://img.shields.io/badge/swift-5.9+-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### 🤖 On-Device LLM Inference
- Powered by [MLX](https://github.com/ml-explore/mlx-swift) — Apple's machine learning framework optimized for Apple Silicon
- Download and manage models directly from Hugging Face
- Curated selection of coding-focused models (Qwen2.5-Coder, CodeGemma, Llama, etc.)
- Smart memory management with KV-cache optimization for long conversations

### 🛠️ Tool Calling
The LLM can interact with your filesystem through a sandboxed tool system:

| Tool | Description |
|------|-------------|
| `read` | Read file contents |
| `write` | Create or overwrite files |
| `edit` | Surgical find-and-replace edits |
| `bash` | Execute filesystem commands (ls, cat, find, grep, mkdir, rm, cp, mv, etc.) |

### 📁 Project Management
- Open any local folder as a working directory
- Browse and navigate project files
- Focus specific files to include in context with `@filename` mentions

### 🔗 Git Integration
- Clone repositories from GitHub
- Sync changes with remote repos
- View branch status and commit history
- OAuth-based GitHub authentication

### 💬 Conversation Management
- Persistent conversation history
- Create, switch between, and delete conversations
- Session restoration with KV-cache rehydration

### 🎨 Clean, Minimal UI
- Monospace-focused design language
- Dark theme optimized for coding
- Responsive layout for iPhone, iPad, and Mac

## Requirements

- **iOS**: iOS 17.0+
- **macOS**: macOS 14.0+ (Apple Silicon required for MLX)
- **Xcode**: 15.0+
- **Memory**: 8GB+ RAM recommended (16GB+ for larger models)

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/codybontecou/LocalCoder.git
cd LocalCoder
```

### 2. Open in Xcode

```bash
open LocalCoder.xcodeproj
```

### 3. Build & Run

1. Select your target device (iPhone, iPad, or Mac)
2. Press `Cmd + R` to build and run
3. The app will resolve Swift Package dependencies automatically:
   - [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) (MLXLLM, MLXLMCommon)
   - [swift-transformers](https://github.com/huggingface/swift-transformers) (Hub, Tokenizers)

### 4. Download a Model

On first launch:
1. Tap the model selector or use `/model` command
2. Choose a model to download (smaller models like Qwen2.5-Coder-0.5B are good starting points)
3. Wait for the download to complete
4. The model will load automatically

### 5. Start Coding

- Open a project folder with the folder picker
- Ask the assistant to explore, edit, or create files
- Use `@filename` to focus context on specific files
- Use `/tools` to toggle available tools on/off

## Slash Commands

| Command | Description |
|---------|-------------|
| `/new` | Start a new conversation |
| `/model` | Select or download a model |
| `/tools` | Toggle tools on/off |
| `/clear` | Clear chat history |
| `/help` | Show available commands |

## Recommended Models

| Model | Size | Best For |
|-------|------|----------|
| Qwen2.5-Coder-0.5B | ~500MB | Quick responses, lower memory devices |
| Qwen2.5-Coder-1.5B | ~1.5GB | Good balance of speed and quality |
| Qwen2.5-Coder-3B | ~3GB | Higher quality code generation |
| CodeGemma-2B | ~2GB | Strong instruction following |

Larger models require more RAM. On iOS, stick to models under 3B parameters for best performance.

## Project Structure

```
LocalCoder/
├── LocalCoderApp.swift      # App entry point
├── ContentView.swift        # Main navigation
├── Models/
│   ├── Message.swift        # Chat message model
│   └── Conversation.swift   # Conversation model
├── Views/
│   ├── ChatView.swift       # Main chat interface
│   ├── FilesView.swift      # File browser
│   ├── GitView.swift        # Git status/sync
│   ├── SettingsView.swift   # App settings
│   └── ...
├── ViewModels/
│   ├── ChatViewModel.swift  # Chat logic
│   └── ...
├── Services/
│   ├── LLMService.swift     # MLX model loading & inference
│   ├── ModelManager.swift   # Model download & management
│   ├── FileService.swift    # File I/O operations
│   ├── ToolExecutor.swift   # Tool call execution
│   ├── GitService.swift     # GitHub API integration
│   └── ...
└── Theme/
    └── LocalCoderTheme.swift # UI constants
```

## Configuration

### GitHub Integration (Optional)

To enable Git sync features:
1. Go to Settings → GitHub
2. Authenticate with your GitHub account
3. Clone and sync repositories directly from the app

### Custom Models

You can add custom MLX model folders:
1. Place the model folder in the app's Documents/Models directory
2. The model will appear in the model selector automatically

Model folders must contain:
- `config.json`
- `tokenizer.json` or `tokenizer_config.json`
- `*.safetensors` weight files

## Memory Management

LocalCoder implements aggressive memory management for iOS:
- KV-cache is reset after 12 turns (40 on macOS)
- Memory warnings trigger session cleanup
- Models are checked against device memory budget before loading
- MLX cache is cleared after each generation

## Contributing

Contributions are welcome! Please open an issue or submit a PR.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- [MLX](https://github.com/ml-explore/mlx) by Apple
- [Hugging Face](https://huggingface.co/) for model hosting
- [swift-transformers](https://github.com/huggingface/swift-transformers) for tokenization
