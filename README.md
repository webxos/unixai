# UNIXAI – Under Development
```
    ▘  ▄▖▄▖
▌▌▛▌▌▚▘▌▌▐ 
▙▌▌▌▌▞▖▛▌▟▖
```
Version 3.6 – A minimalist, single‑script bash harness that turns any local Ollama model into an autonomous conversational agent with an endless reflection mode, message queue, and built‑in tool‑calling.

---

## Overview

UNIXAI is a self‑contained Bash script that designed to run off one bash entirely in your terminal. It connects to a local Ollama server and lets you chat with any model. It offers a unique **Reflection Loop** – a self‑dialogue where the AI continuously responds to its own previous messages, simulating a conversation between a user and an assistant. The loop can be started with any initial prompt and runs indefinitely until you interrupt it.

Agent capabilities (command suggestion via `<cmd>...</cmd>` tags) are always active, making it useful for system administration, development, or exploring model behavior.

---

## Features

- **Reflection Loop** – `/reflect on <prompt>` starts an autonomous self‑dialogue: the AI replies to itself, alternating between `User (Reflect)` and `AI` roles. Perfect for brainstorming, idea refinement, or testing model reasoning.
- **Message Queue** – Conversation history is stored and automatically trimmed based on message count and character limits (configurable), helping smaller models stay within context window.
- **Thinking Visualizer** – A live elapsed‑time spinner shows how long the model is taking to respond.
- **Agent Mode Always On** – The model can propose shell commands using `<cmd>...</cmd>` tags; you are prompted to execute, skip, or run with `sudo`.
- **Model Switching** – List available models and switch at runtime with `/model`.
- **Debugging** – Toggle debug output with `/debug on/off`.
- **Pure Bash** – No external dependencies beyond `curl` and `ollama` (which the script will install if missing).
- **Non‑interactive Fallback** – When `/dev/tty` is unavailable, falls back to first model or `UNIXAI_MODEL` environment variable.

---

## Requirements

- **Linux / macOS / WSL** with Bash 4+.
- **Ollama** – (Local Only) installed and running (the script will attempt to install and start it if missing).
- **Network** – local access to Ollama (default `http://127.0.0.1:11434`).

Optional (for better JSON parsing): `jq` or `python3`. If neither is present, a pure‑awk fallback is used.

---

## Installation

UNIXAI is a single Bash block. To install:

Copy the entire file (`bash << 'UNIXAI_SCRIPT_END' ...`) block and paste it into your terminal – it will run immediately.

---

## Usage

Start the script; it will prompt you to select a model. Then you can interact:

- Type any message to send it to the model.
- Use **slash commands** (see below) to control the session.

### Reflection Loop (Self‑Dialogue)

To start the endless loop with an initial prompt:
```
/reflect on write a short story about a robot
```

This starts a 1:1 loop between the AI> agent and the User (Reflect)> agent. The loop continues until you:
- Type `/reflect off`
- Or type any normal message (which will break the loop and become your next user input)

### Agent Commands

If the model includes a command like `<cmd>ls -la</cmd>`, you will be prompted:
```
>>> Proposed command: ls -la
Run it? [y/N/s=with sudo]
```
- `y` – execute immediately
- `s` – execute with `sudo`
- `N` (or anything else) – skip

---

## Basic Commands

| Command | Description |
|---------|-------------|
| `/reflect on [prompt]` | Start self‑dialogue loop with optional initial prompt |
| `/reflect off` | Stop the loop and return to normal chat |
| `/model` | List available models and switch to a different one |
| `/history` | Show the current message queue (with roles and content) |
| `/clear_history` | Clear the conversation history |
| `/tools` | Show agent capabilities (command execution) |
| `/clear` | Clear the terminal screen |
| `/debug on/off` | Toggle debug logging |
| `/help` | Display this help |
| `exit`, `quit`, `q` | Exit UNIXAI |

---

## Advanced Configuration

All settings can be overridden before running the script:

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_HOST` | `http://127.0.0.1:11434` | Ollama server URL |
| `UNIXAI_MODEL` | (none) | Pre‑select a model; if not found, script exits |
| `REFLECT_MAX_ITERATIONS` | `100000` | Safety cap for loop iterations |
| `MAX_HISTORY_MESSAGES` | `30` | Max number of messages kept in queue |
| `MAX_CONTEXT_CHARS` | `8000` | Approximate character limit for the context |
| `UNIXAI_TEMPERATURE` | `0.8` | Sampling temperature for generation |
| `UNIXAI_DEBUG` | `0` | Set to `1` to enable debug output at start |

Example:
```bash
UNIXAI_MODEL=llama3.2 REFLECT_MAX_ITERATIONS=500 ./unixai.sh
```

---

## Examples

### 1. Example: Start a reflection loop on a coding task
```
/reflect on write a bash function to check if a port is open
```

The AI will generate a function, then respond to its own output, improving and refining the code.

### 2. Example: Use the model for system administration (agent mode)
```
You> list all files in /tmp that are older than 7 days
AI> You can use: find /tmp -type f -mtime +7 <cmd>find /tmp -type f -mtime +7</cmd>
>>> Proposed command: find /tmp -type f -mtime +7
Run it? [y/N/s=with sudo] y
[output...]
```

### 3. Example: Switch models during a session
```
/model
Available models:
   1) llama3.2
   2) qwen2.5:0.5b
Enter number, model name, or 'q' to quit: 2
Switched to model: qwen2.5:0.5b
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `Ollama not found` | The script will try to install it automatically. If that fails, install manually: `curl -fsSL https://ollama.com/install.sh \| sh` |
| `Failed to connect to Ollama` | Ensure Ollama is running (`ollama serve`). Check `OLLAMA_HOST` if using a custom address. |
| `Reflection loop stops or repeats` | Increase `MAX_HISTORY_MESSAGES` and `MAX_CONTEXT_CHARS` to retain more context, or raise `UNIXAI_TEMPERATURE` for more variation. |
| `Command execution not working` | You must type `y` or `s` when prompted. Commands are run in the current shell; `sudo` may require a password. |
| `JSON parse errors` | Install `jq` for more reliable parsing: `sudo apt install jq` (Debian/Ubuntu) or `brew install jq` (macOS). |

---

## License

MIT
