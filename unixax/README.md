**UNDER DEVELOPMENT:**
UNIXAX: Ollama Arsenal — a modular Swiss-army-knife CLI that orchestrates the embedded .sh harnesses (UnixAI, Agent Spin, Auto-Heal + 4 new tools including a GraphJSON benchmark). Everything is self-contained, drop-in modular, auto-installs, auto-launches

UNIXAX sits at the extreme minimalist end: zero install beyond Bash + curl + Ollama (jq optional), fully local, easy to read/audit/extend, and deliberately “Unix philosophy.” It trades sophistication (robust structured tools, long-horizon memory, parallel agents, safety sandboxes) for portability and simplicity. The specialized modes (especially auto-heal and the GraphJSON benchmark) and the “everything is a Bash function in one file” packaging are distinctive, but the core agent loop (prompt → model → optional command tags → feedback) is standard.

