# TRT Loop Local Harness

**Automated iterative Test-time Recursive Thinking (TRT) loop using Ollama.**

A self-improving reasoning harness that runs a recursive **Generate → Select → Reflect** cycle against a local Ollama model. It accumulates a negative-constraint knowledge list (`K`) to drive continuous self-correction on complex problems (reasoning, coding, math, etc.).

All state is persisted in a Git-enabled workspace on your Desktop.

---

## Features

- Interactive problem input (multi-line via `Ctrl+D`)
- Recursive Generate–Select–Reflect loop
- Accumulating negative-constraint list for self-correction
- Persistent state (`state.json`) + per-round transcripts
- Git-backed workspace with automatic commits
- Optional auto-push to remote
- Configurable max rounds (or infinite)
- Automatic dependency detection & installation
- Robust Ollama request retries + timeout handling
- Clean exit with final answer written to disk

---

## Requirements

- **Ollama** running locally (`http://localhost:11434`)
- A model already pulled (default: `qwen2.5:0.5b`)
- Bash
- Dependencies (auto-installed if missing):
  - `jq`
  - `curl`
  - `bc`
  - `cpulimit` (optional)

Supported package managers: `apt`, `brew`, `yum`, `dnf`.

---

## Quick Start

1. Make the script executable:
   ```bash
   chmod +x trt_loop.sh
   ```

2. Ensure Ollama is running and the model is available:
   ```bash
   ollama serve
   ollama pull qwen2.5:0.5b
   ```

3. Run the harness:
   ```bash
   bash trt_loop.sh          # infinite rounds
   bash trt_loop.sh 10       # stop after 10 rounds
   ```

4. Paste your complex problem, then press **Ctrl+D**.

5. Press **Ctrl+C** at any time to stop. The best answer is written to  
   `~/Desktop/trt_final_answer.txt`.

---

## Configuration

Edit the variables at the top of `trt_loop.sh`:

| Variable            | Default                          | Description                                      |
|---------------------|----------------------------------|--------------------------------------------------|
| `MODEL_NAME`        | `qwen2.5:0.5b`                   | Ollama model to use                              |
| `OUTPUT_FILE`       | `~/Desktop/trt_final_answer.txt` | Where the final answer is written                |
| `MAX_ROUNDS`        | `0`                              | Max iterations (`0` = infinite)                  |
| `WORKSPACE_BASE`    | `~/Desktop/TRT_Workspace`        | Base directory for run workspaces                |
| `OLLAMA_MAX_TIMEOUT`| `6000`                           | Max seconds per Ollama request (`0` = infinite)  |
| `CURL_RETRIES`      | `3`                              | Number of retries on failed requests             |
| `CURL_RETRY_DELAY`  | `2`                              | Initial retry delay (seconds, doubles each time) |
| `AUTO_PUSH`         | `false`                          | Auto `git push` after each commit                |
| `CLEAN_WORKSPACE`   | `false`                          | Delete workspace on exit                         |
| `AUTO_INSTALL_DEPS` | `true`                           | Automatically install missing packages           |

---

## How It Works

1. **Input** – You supply a complex problem.
2. **Workspace** – A unique directory is created under `WORKSPACE_BASE` and initialized as a Git repo.
3. **Round loop**:
   - Load current best answer + negative constraints.
   - Prompt the model to produce an improved answer while avoiding all listed constraints.
   - Model also returns an updated constraint list.
   - State is saved, round transcript is archived, and a Git commit is made.
4. **Exit** – On `Ctrl+C` or max rounds reached, the best answer is written to `OUTPUT_FILE`.

### Prompt Contract

The model is instructed to return **only** a JSON object:

```json
{
  "new_answer": "...",
  "updated_constraints": ["constraint1", "constraint2", ...]
}
```

---

## Workspace Layout

```
~/Desktop/TRT_Workspace/
└── TRT_<hash>_<timestamp>/
    ├── README.md              # auto-generated
    ├── state.json             # full run state
    ├── trt_loop.log           # human-readable log
    └── rounds/
        ├── round_1.json
        ├── round_2.json
        └── ...
```

---

## Stopping & Cleanup

- **Ctrl+C** or **SIGTERM** triggers graceful cleanup.
- Final answer is always written (if one exists).
- Set `CLEAN_WORKSPACE="true"` to automatically delete the workspace on exit.

---

## Tips

- Use a stronger model for better results (`llama3.1:8b`, `qwen2.5:7b`, etc.).
- Start with a modest `MAX_ROUNDS` (e.g. 5–15) while tuning.
- Review `state.json` and the `rounds/` folder to inspect the reasoning trajectory.
- Enable `AUTO_PUSH` only after you have configured a remote:
  ```bash
  cd <workspace>
  git remote add origin <your-repo-url>
  ```

---

## License

MIT
