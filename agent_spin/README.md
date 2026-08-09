# 🌀 UNIXAI: AGENT SPIN – Autonomous Code Factory (Under Development)

**Infinite Loop • Git Auto‑Commit • Local LLM Driven • Production‑Ready**

AGENT SPIN is a **self‑running, continuously building code generator** that uses a local Ollama model to autonomously write, test, fix, and version‑control complete software projects. Just set your preferred model once, give it a goal, and watch it create a new project every cycle. It's built off the basic unixai.sh harness format.

---

## ✨ Features

- 🧠 **Uses any Ollama model** – pick your favourite, set it in the script, and go.
- ♾️ **Infinite loop** – keeps generating new iterations until you press `Ctrl+C` or reach a configured maximum.
- ⏱️ **Configurable timeouts** – test runs and Ollama generation have finite limits to prevent hanging.
- 📁 **Each cycle = a fresh project** – all source code and tests in a new, uniquely named folder.
- 🔧 **Proactive syntax checking** – fixes syntax errors before running tests, saving retries.
- 🛠️ **Automatic test‑and‑repair** – if tests fail, the LLM patches the code (both test and app) up to 3 times.
- 📦 **Git version control out of the box** – every cycle (even failed ones) is committed.
- 🚀 **Optional auto‑push** – enable automatic git push to a remote repository via a configuration flag.
- 🧹 **Zero extra commands** – no model picker, no CLI options; edit the script once and run.
- 🔢 **Cycle limit** – you can optionally stop after a set number of cycles.

---

## 📦 Requirements

- [Ollama](https://ollama.com/) installed and running, with at least one model downloaded (e.g., `llama3.2`, `qwen2.5`, etc.).
- `curl` (for API communication).
- **`jq`** – required for robust JSON parsing.
- `git` (optional – skip if not needed).
- Bash 3+ (Linux, macOS, WSL).

---

## 🚀 Quick Start

1. **Download** or copy the `agent_spin.sh` script.

2. **Edit the model** (optional – default is `qwen2.5:0.5b`):
   ```bash
   MODEL_NAME="llama3.2"      # change to your preferred model
   ```

3. **Run it** (no `chmod` needed):
   ```bash
   bash agent_spin.sh
   ```
   You can also pass a goal and optional cycle limit:
   ```bash
   bash agent_spin.sh "a REST API in Python" 10
   ```

4. **Answer the goal question** if not provided – e.g., *“a REST API in Python”*.

5. **Let it run** – the script will cycle indefinitely (or until the cycle limit), creating new projects and committing successes.

6. **Stop** – press `Ctrl+C` at any time.

---

## 🔧 Configuration (directly inside the script)

| Variable | Description | Default |
|----------|-------------|---------|
| `OLLAMA_URL` | API endpoint for Ollama | `http://localhost:11434/api/generate` |
| `MODEL_NAME` | Model to use | `qwen2.5:0.5b` |
| `MAX_TEST_RETRIES` | Repair attempts per cycle | `3` |
| `TEST_TIMEOUT` | Seconds to wait for tests before killing | `60` |
| `OLLAMA_MAX_TIMEOUT` | Max seconds for Ollama generation (`0` = infinite, but we recommend finite) | `600` |
| `AUTO_PUSH` | Automatically `git push` after each commit | `false` |
| `WORKSPACE_BASE` | Base directory for workspace | `~/Desktop` |
| `MAX_CYCLES` | Stop after N cycles (0 = infinite) | `0` |
| `CLEAN_NODE_MODULES` | Remove `node_modules` after each cycle | `false` |

### Enabling Auto‑Push to Remote

Set `AUTO_PUSH="true"` and make sure your Git repository has a remote configured (e.g., `git remote add origin https://github.com/your/repo.git`).  
The script will automatically `git push` after each successful commit.

---

## 📂 Output Structure

A new workspace is created in the configured base directory (default `~/Desktop`):

```
~/Desktop/AGENT_FORGE_<hash>_<timestamp>/
├── agent.log                # Full activity log
├── README.md                # Workspace readme
├── .git/                    # Git repository (if Git installed)
├── Cycle_1_python/          # First cycle
│   ├── app.py
│   └── test_app.py
├── Cycle_2_nodejs/          # Second cycle
│   ├── app.js
│   └── test_app.js
└── ...
```

Each `Cycle_N_lang` is a self‑contained project. The script never overwrites previous cycles – it only adds new ones.

---

## ⚙️ Automation Pipeline

1. **Ideate** – The LLM chooses a runtime (`python`, `nodejs`, or `bash`) based on your goal.
2. **Build** – The LLM generates the application and a corresponding test file.
3. **Pre‑test Syntax Check** – Both files are syntax‑checked; any errors are fixed immediately.
4. **Test** – The tests are executed with a timeout. If they fail:
   - The test file is fixed first (if possible), then the application.
   - Up to `MAX_TEST_RETRIES` attempts are made.
5. **Commit** – After each cycle, the entire workspace is `git add`ed and committed (even if tests failed) with a descriptive message.
6. **Push (optional)** – If `AUTO_PUSH` is enabled, the commit is pushed to the remote.
7. **Loop** – The cycle repeats indefinitely or until `MAX_CYCLES` is reached.

---

## ⏱️ Timeout Design

Unlike earlier versions, AGENT SPIN now uses **finite timeouts** for both test execution and Ollama generation:

- **Test timeout** – `TEST_TIMEOUT` seconds; if a test hangs, it is killed.
- **Ollama timeout** – `OLLAMA_MAX_TIMEOUT` seconds; if the model takes too long, the request is aborted and the cycle is retried.

This prevents the script from hanging indefinitely due to slow or stuck responses.

---

## 🛠️ Troubleshooting

| Issue | Solution |
|-------|----------|
| **Error: `jq` not found** | Install `jq` – it is **required**. |
| **Error: `Cannot reach Ollama`** | Ensure Ollama is running (`ollama serve`). |
| **Model not found** | Verify the model name in the script exists locally (`ollama list`). |
| **Git commit fails** | The script warns but continues – version control is optional. |
| **No output / hanging** | The model may be slow – check the log file (`agent.log`) inside the workspace. If generation times out, increase `OLLAMA_MAX_TIMEOUT`. |
| **Permission errors** | Run with `bash` (no `chmod` needed). For Bash projects, the script already sets executable bits. |
| **Disk space** | New cycles are created indefinitely – monitor free space or set `MAX_CYCLES` to limit. |

---

## 📄 License

MIT

**Happy building!** 🏭
```
