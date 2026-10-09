bash << 'UNIXSI_SCRIPT_END'
#!/usr/bin/env bash
#
# UNIXSI – pure‑bash Ollama harness with Endless Reflection (self‑dialogue loop)
# Version: 3.6 (reflection prefix now "User (Reflect)>", exact loop flow)
# Debug: /debug on  (or set UNIXSI_DEBUG=1)
# Run: copy-paste this whole block into any terminal – Bash is auto‑used.
#
# Environment:
#   OLLAMA_HOST          – override Ollama URL (default: http://127.0.0.1:11434)
#   REFLECT_MAX_ITERATIONS – safety cap (default: 100000)
#   UNIXSI_MODEL         – pre‑select a model; if invalid, exits
#   MAX_HISTORY_MESSAGES – max messages in queue (default: 30)
#   MAX_CONTEXT_CHARS    – rough char limit for context (default: 8000)
#   UNIXSI_TEMPERATURE   – sampling temperature (default: 0.8)

set -euo pipefail

# ------------------------------- Initialize flags ------------------------------
UNIXSI_EXITED=""
SKIP_WAIT=0
REFLECT=0
REFLECT_COUNT=0
REFLECT_RETRY_COUNT=0
REFLECT_NEXT_INPUT=""
IS_REFLECTION_INPUT=0
MODEL=""

# ------------------------------- Configurable parameters -----------------------
OLLAMA_URL="${OLLAMA_HOST:-http://127.0.0.1:11434}"
REFLECT_MAX_ITERATIONS="${REFLECT_MAX_ITERATIONS:-100000}"
UNIXSI_MODEL="${UNIXSI_MODEL:-}"
MAX_HISTORY_MESSAGES="${MAX_HISTORY_MESSAGES:-30}"
MAX_CONTEXT_CHARS="${MAX_CONTEXT_CHARS:-8000}"
UNIXSI_TEMPERATURE="${UNIXSI_TEMPERATURE:-0.8}"

# ------------------------------- Debug flag ------------------------------------
DEBUG=${UNIXSI_DEBUG:-0}
debug_log() {
    if [ "$DEBUG" -eq 1 ]; then
        echo "[DEBUG] $*" >&2
    fi
}

# ------------------------------- EXIT trap (with skip) -------------------------
cleanup() {
    if [ -z "$UNIXSI_EXITED" ]; then
        UNIXSI_EXITED=1
        if [ $SKIP_WAIT -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
            echo
            echo "UNIXSI session finished."
            echo "Press Enter to close this window."
            read -r < /dev/tty 2>/dev/null || true
        fi
    fi
}
trap cleanup EXIT

int_handler() {
    echo
    echo "Interrupted by user."
    SKIP_WAIT=1
    exit 1
}
trap int_handler INT
trap int_handler TERM

# ------------------------------- Message Queue ---------------------------------
declare -a MSG_HISTORY=()
MSG_HISTORY_CHARS=0

add_message() {
    local role="$1"
    local content="$2"
    local entry="$role:$content"
    MSG_HISTORY+=("$entry")
    MSG_HISTORY_CHARS=$((MSG_HISTORY_CHARS + ${#content} + ${#role} + 1))
    trim_history
}

trim_history() {
    while [[ ${#MSG_HISTORY[@]} -gt $MAX_HISTORY_MESSAGES ]] || [[ $MSG_HISTORY_CHARS -gt $MAX_CONTEXT_CHARS ]]; do
        if [[ ${#MSG_HISTORY[@]} -eq 0 ]]; then
            break
        fi
        local oldest="${MSG_HISTORY[0]}"
        MSG_HISTORY_CHARS=$((MSG_HISTORY_CHARS - ${#oldest}))
        MSG_HISTORY=("${MSG_HISTORY[@]:1}")
    done
}

clear_history() {
    MSG_HISTORY=()
    MSG_HISTORY_CHARS=0
    echo "Message history cleared."
}

show_history() {
    if [[ ${#MSG_HISTORY[@]} -eq 0 ]]; then
        echo "Message history is empty."
        return
    fi
    echo "Message history (${#MSG_HISTORY[@]} messages, ~${MSG_HISTORY_CHARS} chars):"
    for entry in "${MSG_HISTORY[@]}"; do
        local role="${entry%%:*}"
        local content="${entry#*:}"
        echo "[$role] $content"
    done
}

build_prompt() {
    local full_prompt=""
    local base_sys="You are a helpful Unix assistant running inside a minimal bash harness. You may propose shell commands by wrapping them exactly like this: <cmd>the command</cmd>. Never invent other tags."
    if [ $REFLECT -eq 1 ]; then
        # Add extra instruction for reflection mode – treat your previous response as the user's new message.
        base_sys="$base_sys

You are currently in a self‑dialogue loop. Your previous response will be sent back to you as a user message. Reply to that message as if you are a helpful assistant continuing the conversation – be creative, provide new insights, and never repeat the exact same answer."
    fi
    full_prompt="$base_sys
"
    for entry in "${MSG_HISTORY[@]}"; do
        local role="${entry%%:*}"
        local content="${entry#*:}"
        if [[ "$role" == "user" ]]; then
            full_prompt+="User: $content
"
        elif [[ "$role" == "assistant" ]]; then
            full_prompt+="Assistant: $content
"
        else
            full_prompt+="$role: $content
"
        fi
    done
    full_prompt+="Assistant:"
    printf '%s' "$full_prompt"
}

# ------------------------------- JSON helpers (robust) -------------------------
json_escape() {
    local input="$1"
    if command -v jq &>/dev/null; then
        printf '%s' "$input" | jq -Rs .
    elif command -v python3 &>/dev/null; then
        python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))' <<< "$input" 2>/dev/null
    else
        printf '%s' "$input" | awk '
            BEGIN { printf "\"" }
            {
                gsub(/\\/, "\\\\")
                gsub(/"/, "\\\"")
                gsub(/\t/, "\\t")
                gsub(/\r/, "\\r")
                gsub(/\f/, "\\f")
                gsub(/\v/, "\\v")
                if (NR > 1) printf "\\n"
                printf "%s", $0
            }
            END { printf "\"" }
        '
    fi
}

extract_response() {
    if command -v jq &>/dev/null; then
        jq -r '.response // ""'
    elif command -v python3 &>/dev/null; then
        python3 -c 'import sys, json; print(json.load(sys.stdin).get("response", ""))' 2>/dev/null
    else
        awk '
            BEGIN { resp=""; in_response=0; escape=0; }
            {
                if (!in_response) {
                    idx = index($0, "\"response\"")
                    if (idx) {
                        rest = substr($0, idx)
                        colon = index(rest, ":")
                        if (colon) {
                            rest = substr(rest, colon+1)
                            gsub(/^[[:space:]]*/, "", rest)
                            if (substr(rest, 1, 1) == "\"") {
                                in_response=1
                                rest = substr(rest, 2)
                                while (length(rest) > 0) {
                                    if (escape) {
                                        resp = resp "\\" substr(rest, 1, 1)
                                        escape = 0
                                        rest = substr(rest, 2)
                                    } else if (substr(rest, 1, 1) == "\\") {
                                        escape = 1
                                        rest = substr(rest, 2)
                                    } else if (substr(rest, 1, 1) == "\"") {
                                        in_response=0
                                        break
                                    } else {
                                        resp = resp substr(rest, 1, 1)
                                        rest = substr(rest, 2)
                                    }
                                }
                                gsub(/\\n/, "\n", resp)
                                gsub(/\\t/, "\t", resp)
                                gsub(/\\r/, "\r", resp)
                                gsub(/\\f/, "\f", resp)
                                gsub(/\\v/, "\v", resp)
                                print resp
                                exit
                            }
                        }
                    }
                }
            }
        '
    fi
}

# ----------------------------------- Thinking Visualizer -----------------------
show_thinking() {
    local pid=$1
    if [ ! -t 1 ]; then
        wait "$pid" 2>/dev/null || true
        return 0
    fi
    local start_time=$(date +%s)
    local elapsed=0
    local spin='|/-\'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        elapsed=$(( $(date +%s) - start_time ))
        printf "\r\033[KThinking... %s %ds" "${spin:i%4:1}" "$elapsed"
        i=$((i+1))
        sleep 0.2
    done
    wait "$pid" 2>/dev/null || true
    printf "\r\033[K"
    return 0
}

# ----------------------------------- Model listing (robust) --------------------
_parse_ollama_list() {
    models=()
    if ollama list --json 2>/dev/null | grep -q "models" 2>/dev/null; then
        if command -v jq &>/dev/null; then
            while IFS= read -r name; do
                [[ -n "$name" ]] && models+=("$name")
            done < <(ollama list --json 2>/dev/null | jq -r '.models[].name' 2>/dev/null)
        elif command -v python3 &>/dev/null; then
            while IFS= read -r name; do
                [[ -n "$name" ]] && models+=("$name")
            done < <(ollama list --json 2>/dev/null | python3 -c 'import sys, json; data=json.load(sys.stdin); print("\n".join([m["name"] for m in data.get("models", [])]))' 2>/dev/null)
        else
            while IFS= read -r line; do
                [[ -z "$line" || "$line" =~ ^NAME ]] && continue
                name=$(echo "$line" | awk '{print $1}')
                [[ -n "$name" ]] && models+=("$name")
            done < <(ollama list 2>/dev/null)
        fi
    else
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^NAME ]] && continue
            name=$(echo "$line" | awk '{print $1}')
            [[ -n "$name" ]] && models+=("$name")
        done < <(ollama list 2>/dev/null)
    fi
}

list_models() {
    _parse_ollama_list
    if [ ${#models[@]} -eq 0 ]; then
        echo "No models found. Pulling llama3.2 as default..."
        ollama pull llama3.2 >/dev/null 2>&1
        _parse_ollama_list
        if [ ${#models[@]} -eq 0 ]; then
            echo "ERROR: Unable to detect any models. Please install a model manually."
            exit 1
        fi
    fi
}

# ----------------------------------- Command extraction (agent mode always on)--
extract_commands() {
    local response="$1"
    if printf '%s' "$response" | grep -q '<cmd>' && ! printf '%s' "$response" | grep -q '</cmd>'; then
        echo "Warning: Model used an opening <cmd> tag without a closing </cmd>. Ignoring." >&2
        return 1
    fi
    printf '%s' "$response" | awk '
        BEGIN { cmd=""; inside=0; }
        {
            line = $0
            while (length(line) > 0) {
                if (!inside) {
                    idx = index(line, "<cmd>")
                    if (idx == 0) break
                    line = substr(line, idx + 5)
                    inside = 1
                    cmd = ""
                } else {
                    idx = index(line, "</cmd>")
                    if (idx == 0) {
                        cmd = cmd line "\n"
                        break
                    } else {
                        cmd = cmd substr(line, 1, idx - 1)
                        printf "%s%c", cmd, 0
                        inside = 0
                        line = substr(line, idx + 6)
                        cmd = ""
                    }
                }
            }
        }
        END {
            if (inside && length(cmd) > 0) {
                printf "%s%c", cmd, 0
            }
        }
    '
}

# ----------------------------------- Server readiness --------------------------
start_ollama() {
    if ! curl -s --max-time 2 "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
        echo "Starting ollama serve..."
        nohup ollama serve >/tmp/ollama-unixsi.log 2>&1 &
        sleep 2
        local wait_sec=0
        while [ $wait_sec -lt 30 ]; do
            if curl -s --max-time 2 "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
                echo "Ollama server is ready."
                return 0
            fi
            sleep 1
            ((wait_sec++))
        done
        echo "WARNING: Ollama server may not be fully ready. Proceeding anyway."
    else
        echo "Ollama server already running."
    fi
}

# ----------------------------------- Send a prompt and get response -----------
send_prompt() {
    local model="$1"
    local prompt="$2"
    local temp="${UNIXSI_TEMPERATURE}"

    local escaped=$(json_escape "$prompt")
    debug_log "Sending prompt to $model: $escaped"

    local body_file=$(mktemp)
    local status_file=$(mktemp)
    local error_file=$(mktemp)

    {
        curl -s --max-time 300 --fail \
            -w "%{http_code}" \
            -o "$body_file" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$model\",\"prompt\":$escaped,\"stream\":false,\"temperature\":$temp}" \
            "$OLLAMA_URL/api/generate" \
            2> "$error_file"
    } > "$status_file" &

    local curl_pid=$!
    show_thinking $curl_pid
    local http_status=$(cat "$status_file" 2>/dev/null || echo "000")

    debug_log "HTTP status: $http_status"
    debug_log "Curl error: $(cat "$error_file")"

    if [ "$http_status" != "200" ]; then
        echo "SI> [Error: Ollama request failed (HTTP $http_status)]" >&2
        if [ -s "$error_file" ]; then
            echo "Details: $(cat "$error_file")" >&2
        fi
        if [ -s "$body_file" ]; then
            echo "Response body:" >&2
            cat "$body_file" >&2
        fi
        rm -f "$body_file" "$status_file" "$error_file"
        return 1
    fi

    local response=$(extract_response < "$body_file")
    rm -f "$body_file" "$status_file" "$error_file"

    if [ -z "$response" ]; then
        echo "SI> [Warning: Empty response from model]" >&2
        return 1
    fi

    echo "$response"
    return 0
}

# ----------------------------------- Model selection helper (plain menu) ------
select_model() {
    if [ -n "$UNIXSI_MODEL" ]; then
        for m in "${models[@]}"; do
            if [ "$m" = "$UNIXSI_MODEL" ]; then
                MODEL="$m"
                echo "Using model from environment: $MODEL"
                return 0
            fi
        done
        echo "ERROR: UNIXSI_MODEL='$UNIXSI_MODEL' is not available. Exiting."
        exit 1
    fi

    local attempts=0
    local max_attempts=5
    while true; do
        echo "Available models:"
        for i in "${!models[@]}"; do
            printf "  %2d) %s\n" $((i+1)) "${models[i]}"
        done
        printf "Enter number, model name, or 'q' to quit: "
        read -r choice < /dev/tty 2>/dev/null || break

        case "$choice" in
            q|quit|exit)
                echo "Exiting."
                exit 0
                ;;
            [0-9]*)
                if [ "$choice" -ge 1 ] && [ "$choice" -le "${#models[@]}" ]; then
                    MODEL="${models[$((choice-1))]}"
                    return 0
                else
                    echo "Invalid number. Try again."
                fi
                ;;
            *)
                found=0
                for m in "${models[@]}"; do
                    if [ "$choice" = "$m" ]; then
                        MODEL="$m"
                        found=1
                        return 0
                    fi
                done
                if [ $found -eq 0 ]; then
                    echo "Invalid model name. Try again."
                fi
                ;;
        esac
        attempts=$((attempts + 1))
        if [ $attempts -ge $max_attempts ]; then
            echo "Too many invalid attempts. Exiting."
            exit 1
        fi
    done
    # Non-interactive fallback
    if [ -z "${MODEL:-}" ] && [ ${#models[@]} -gt 0 ]; then
        MODEL="${models[0]}"
        echo "Non-interactive mode: using first model '$MODEL'."
        return 0
    fi
    echo "ERROR: Cannot select model. Exiting."
    exit 1
}

# ----------------------------------- ASCII banner ------------------------------
ascii_banner() {
    cat << "BANNER_EOF"
▖▖▖ ▖▄▖▖▖▄▖▄▖
▌▌▛▖▌▐ ▚▘▚ ▐ 
▙▌▌▝▌▟▖▌▌▄▌▟▖
    UNIXSI – Agent Harness
BANNER_EOF
}

# ----------------------------------- help / tools ------------------------------
show_help() {
    cat <<EOF
Available commands:
  /tools             - Show available agent capabilities (command execution)
  /model             - List and switch to another model
  /clear             - Clear the terminal screen
  /help              - Show this help
  /debug on/off      - Toggle debug mode

  # Message Queue (for context management)
  /history           - Show message history
  /clear_history     - Clear the message queue

  # Reflection (self‑dialogue loop):
  /reflect on [prompt] - Start autonomous loop with an initial prompt
                         (the prompt becomes the first "User (Reflect)" message)
  /reflect off       - Stop the loop and return to normal interactive mode

  exit, quit, q      - Exit UNIXSI

Anything else is sent as a prompt to the selected Ollama model.

Agent capabilities are always active:
  The model can suggest shell commands by wrapping them in <cmd>...</cmd>.
  When a command is proposed, you will be prompted to:
    y   - execute it directly
    s   - execute with sudo
    N   - skip (default)
EOF
}

show_tools() {
    cat <<EOF
Agent capabilities are always active:
  The model can suggest shell commands by wrapping them in <cmd>...</cmd>.
  When a command is proposed, you will be prompted to:
    y   - execute it directly
    s   - execute with sudo
    N   - skip (default)
EOF
}

# ----------------------------------- Main --------------------------------------
ascii_banner
echo

if ! command -v jq &>/dev/null && ! command -v python3 &>/dev/null; then
    echo "Hint: Install 'jq' for robust JSON parsing: sudo apt install jq"
    echo "The script will use awk fallback (less reliable)."
    echo
fi

if ! command -v ollama &>/dev/null; then
    echo "Ollama missing — installing (official script)..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

start_ollama

list_models
if [ ${#models[@]} -eq 0 ]; then
    echo "ERROR: No models available. Exiting."
    exit 1
fi

select_model
echo "Using model: $MODEL"
echo "Temperature: $UNIXSI_TEMPERATURE"
echo

echo "UNIXSI ready — type your messages below."
echo
show_help
echo
if [[ $REFLECT -eq 1 ]]; then
    echo "Reflection mode is ON (self‑dialogue loop)."
else
    echo "Reflection mode is OFF. Type /reflect on <prompt> to start the loop."
fi
echo "Message queue: ${#MSG_HISTORY[@]} messages, ~${MSG_HISTORY_CHARS} chars (max ${MAX_HISTORY_MESSAGES} msgs / ${MAX_CONTEXT_CHARS} chars)"
echo

# Agent mode is always on
SYS="You are a helpful Unix assistant running inside a minimal bash harness. You may propose shell commands by wrapping them exactly like this: <cmd>the command</cmd>. Never invent other tags."

while true; do
    # ---------- Read input (with reflection support) ----------
    if [ $REFLECT -eq 1 ]; then
        if [ -n "$REFLECT_NEXT_INPUT" ]; then
            # Use queued reflection input
            INPUT="$REFLECT_NEXT_INPUT"
            REFLECT_NEXT_INPUT=""
            IS_REFLECTION_INPUT=1
        else
            # No queued input, wait for user
            printf "You (reflect)> "
            read -r INPUT < /dev/tty || break
            IS_REFLECTION_INPUT=0
            REFLECT_RETRY_COUNT=0
            # If user typed a command, it will be handled below
        fi
    else
        printf "You> "
        read -r INPUT < /dev/tty || break
        IS_REFLECTION_INPUT=0
        REFLECT_RETRY_COUNT=0
    fi

    # ---------- Process commands ----------
    case "$INPUT" in
        exit|quit|q) echo "bye"; break ;;
        /help)       show_help; continue ;;
        /tools)      show_tools; continue ;;
        /clear)      clear; continue ;;
        /history)    show_history; continue ;;
        /clear_history) clear_history; continue ;;
        /debug\ on)  DEBUG=1; echo "[debug mode ON]"; continue ;;
        /debug\ off) DEBUG=0; echo "[debug mode OFF]"; continue ;;
        /model)
            echo "Fetching available models..."
            list_models
            if [ ${#models[@]} -eq 0 ]; then
                echo "No models found. Please pull a model manually."
                continue
            fi
            select_model
            echo "Switched to model: $MODEL"
            continue
            ;;
        /reflect\ off)
            REFLECT=0
            REFLECT_NEXT_INPUT=""
            REFLECT_RETRY_COUNT=0
            echo "[reflection mode OFF]"
            continue
            ;;
        /reflect\ on*)
            # Extract the prompt: everything after "/reflect on "
            if [[ "$INPUT" =~ ^/reflect\ on\ (.*)$ ]]; then
                prompt="${BASH_REMATCH[1]}"
            else
                prompt=""
            fi
            REFLECT=1
            REFLECT_COUNT=0
            REFLECT_RETRY_COUNT=0
            if [ -n "$prompt" ]; then
                REFLECT_NEXT_INPUT="$prompt"
                echo "[reflection mode ON] starting with prompt: $prompt"
            else
                REFLECT_NEXT_INPUT=""
                echo "[reflection mode ON] (waiting for your first input)"
            fi
            continue
            ;;
        /*)
            echo "Unknown command: $INPUT"
            continue
            ;;
        "") continue ;;
    esac

    # If reflection input, show it before sending
    if [ $IS_REFLECTION_INPUT -eq 1 ]; then
        echo "User (Reflect)> $INPUT"
    fi

    # ---------- Add user message to history ----------
    add_message "user" "$INPUT"

    # ---------- Build the prompt from history ----------
    PROMPT=$(build_prompt)
    debug_log "Built prompt: $PROMPT"

    # ---------- Get response ----------
    if ! RESP=$(send_prompt "$MODEL" "$PROMPT"); then
        # Remove the user message we just added (since it failed)
        if [[ ${#MSG_HISTORY[@]} -gt 0 ]]; then
            MSG_HISTORY=("${MSG_HISTORY[@]:0:${#MSG_HISTORY[@]}-1}")
        fi
        if [ $REFLECT -eq 1 ]; then
            REFLECT_RETRY_COUNT=$((REFLECT_RETRY_COUNT + 1))
            if [ $REFLECT_RETRY_COUNT -gt 5 ]; then
                echo "Reflection retry limit reached. Disabling loop."
                REFLECT=0
                REFLECT_NEXT_INPUT=""
                REFLECT_RETRY_COUNT=0
            else
                echo "SI> [Retry $REFLECT_RETRY_COUNT/5 after error...]" >&2
                sleep 2
            fi
        fi
        continue
    fi
    if [ -z "$RESP" ]; then
        # Empty response, treat as error
        if [[ ${#MSG_HISTORY[@]} -gt 0 ]]; then
            MSG_HISTORY=("${MSG_HISTORY[@]:0:${#MSG_HISTORY[@]}-1}")
        fi
        continue
    fi
    REFLECT_RETRY_COUNT=0

    # ---------- Add assistant response to history ----------
    add_message "assistant" "$RESP"

    # ---------- Print the response ----------
    echo "SI> $RESP"

    # ---------- Prepare next reflection input (if enabled) ----------
    if [ $REFLECT -eq 1 ]; then
        REFLECT_COUNT=$((REFLECT_COUNT + 1))
        if [ $REFLECT_COUNT -ge $REFLECT_MAX_ITERATIONS ]; then
            echo "Reflection safety limit reached. Turning off loop."
            REFLECT=0
            REFLECT_NEXT_INPUT=""
        else
            # Use the SI's own response as the next user input (self‑dialogue)
            REFLECT_NEXT_INPUT="$RESP"
        fi
    fi

    # ---------- Agent mode: extract commands (always active) ----------
    tmp_cmds=$(mktemp)
    if extract_commands "$RESP" > "$tmp_cmds"; then
        if [ -s "$tmp_cmds" ]; then
            echo
            while IFS= read -r -d '' cmd; do
                if [ -n "$cmd" ]; then
                    echo ">>> Proposed command: $cmd"
                    printf "Run it? [y/N/s=with sudo] "
                    read -r ans < /dev/tty || ans=""
                    case "$ans" in
                        y|Y) eval "$cmd" ;;
                        s|S) sudo bash -c "$cmd" ;;
                        *) echo "skipped" ;;
                    esac
                fi
            done < "$tmp_cmds"
        fi
    fi
    rm -f "$tmp_cmds"
done
UNIXSI_SCRIPT_END
