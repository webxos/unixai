#!/usr/bin/env bash
# ==============================================================================
# TRT LOOP LOCAL HARNESS
# Automated iterative Test‑time Recursive Thinking (TRT) loop using Ollama.
# ==============================================================================
# Usage: bash trt_loop.sh [max_rounds]
#
# Prompts for a complex problem, then runs a recursive Generate‑Select‑Reflect
# loop, accumulating a negative‑constraint knowledge list (K) to drive self‑
# correction. All state is saved in a Git‑enabled workspace on your Desktop.
#
# Configuration (edit these variables):
#   MODEL_NAME           - Ollama model (e.g., qwen2.5:0.5b)
#   OUTPUT_FILE          - final answer output (default: ~/Desktop/trt_final_answer.txt)
#   MAX_ROUNDS           - stop after this many rounds (0 = infinite)
#   WORKSPACE_BASE       - where to create workspace (default: ~/Desktop/TRT_Workspace)
#   OLLAMA_MAX_TIMEOUT   - max seconds for Ollama generation (0 = infinite)
#   CURL_RETRIES         - number of retries for Ollama requests
#   CURL_RETRY_DELAY     - initial delay in seconds between retries
#   AUTO_PUSH            - set to "true" to enable automatic git push
#   CLEAN_WORKSPACE      - set to "true" to delete workspace on exit
#   AUTO_INSTALL_DEPS    - set to "true" to automatically install missing packages
# ==============================================================================

# --- CONFIGURATION ------------------------------------------------------------
OLLAMA_URL="http://localhost:11434/api/generate"
MODEL_NAME="qwen2.5:0.5b"
OUTPUT_FILE="${HOME}/Desktop/trt_final_answer.txt"
MAX_ROUNDS=0                         # 0 = infinite
WORKSPACE_BASE="${HOME}/Desktop/TRT_Workspace"
OLLAMA_MAX_TIMEOUT=6000              # 0 for infinite
CURL_RETRIES=3
CURL_RETRY_DELAY=2
AUTO_PUSH="false"
CLEAN_WORKSPACE="false"              # if true, deletes workspace on exit
AUTO_INSTALL_DEPS="true"             # if true, install missing packages automatically

# --- INTERNAL VARIABLES -------------------------------------------------------
ROUND_COUNT=0
WORKSPACE_DIR=""
LOG_FILE=""
STATE_FILE=""
BEST_ANSWER=""                       # accumulated best answer
KNOWLEDGE_LIST="[]"                  # JSON array of constraints

# --- DETECT PACKAGE MANAGER & AUTO-INSTALL DEPENDENCIES -----------------------
detect_pkg_manager() {
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v brew >/dev/null 2>&1; then
        echo "brew"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    else
        echo "unknown"
    fi
}

install_packages() {
    local pkg_manager="$1"
    shift
    local packages=("$@")
    local install_cmd=""

    case "$pkg_manager" in
        apt)
            install_cmd="sudo apt update && sudo apt install -y ${packages[*]}"
            ;;
        brew)
            install_cmd="brew install ${packages[*]}"
            ;;
        yum)
            install_cmd="sudo yum install -y ${packages[*]}"
            ;;
        dnf)
            install_cmd="sudo dnf install -y ${packages[*]}"
            ;;
        *)
            echo "❌ ERROR: Unsupported package manager. Please install the following manually: ${packages[*]}"
            return 1
            ;;
    esac

    echo "📦 Installing missing packages: ${packages[*]}"
    if ! eval "$install_cmd"; then
        echo "❌ ERROR: Failed to install packages. Please install them manually: ${packages[*]}"
        return 1
    fi
    echo "✅ Packages installed successfully."
    return 0
}

check_and_install_deps() {
    local missing=()
    local required_packages=("jq" "curl" "bc")
    local optional_packages=("cpulimit")

    for pkg in "${required_packages[@]}"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done

    if ! command -v cpulimit >/dev/null 2>&1; then
        missing+=("cpulimit")
    fi

    if [ ${#missing[@]} -eq 0 ]; then
        echo "✅ All required dependencies are installed."
        return 0
    fi

    echo "⚠️  Missing packages: ${missing[*]}"
    if [ "$AUTO_INSTALL_DEPS" != "true" ]; then
        echo "❌ Auto-install is disabled. Please install the missing packages manually."
        exit 1
    fi

    local pkg_manager
    pkg_manager=$(detect_pkg_manager)
    if [ "$pkg_manager" = "unknown" ]; then
        echo "❌ ERROR: Could not detect package manager. Please install the missing packages manually: ${missing[*]}"
        exit 1
    fi

    if [[ "$pkg_manager" == "apt" || "$pkg_manager" == "yum" || "$pkg_manager" == "dnf" ]]; then
        if ! command -v sudo >/dev/null 2>&1; then
            echo "❌ ERROR: 'sudo' is required to install packages with $pkg_manager, but it's not installed."
            echo "   Please install the packages manually: ${missing[*]}"
            exit 1
        fi
        if ! sudo -n true 2>/dev/null; then
            echo "🔑 'sudo' password may be required to install packages."
        fi
    fi

    install_packages "$pkg_manager" "${missing[@]}"
    if [ $? -ne 0 ]; then
        exit 1
    fi

    for pkg in "${missing[@]}"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            echo "❌ ERROR: $pkg still not installed after attempt. Please install manually."
            exit 1
        fi
    done
    echo "✅ All dependencies are now installed."
}

# --- RUN DEPENDENCY CHECK -----------------------------------------------------
check_and_install_deps

# --- CHECK OLLAMA -------------------------------------------------------------
check_ollama() {
    local payload
    payload=$(jq -n --arg model "$MODEL_NAME" '{model:$model, prompt:"Hello", stream:false}')
    local http_code response_body
    response_body=$(curl -s -X POST "$OLLAMA_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        -w "\n%{http_code}" 2>/dev/null)
    http_code=$(echo "$response_body" | tail -n1)
    response_body=$(echo "$response_body" | sed '$d')

    if [ "$http_code" != "200" ]; then
        echo "❌ ERROR: Ollama returned HTTP $http_code" >&2
        echo "   Check that Ollama is running and the model exists." >&2
        exit 1
    fi
    local response_text
    response_text=$(echo "$response_body" | jq -r '.response' 2>/dev/null)
    if [ -z "$response_text" ] || [ ${#response_text} -lt 1 ]; then
        echo "❌ ERROR: Ollama did not return a valid response. Model '$MODEL_NAME' not found?" >&2
        echo "   Pull the model with: ollama pull $MODEL_NAME" >&2
        exit 1
    fi
    echo "✅ Ollama ready (model: $MODEL_NAME)"
}

# --- USER INPUT (Problem) -----------------------------------------------------
gather_user_input() {
    echo "======================================================================"
    echo "🧠 TRT LOOP – Recursive Thinking Harness"
    echo "======================================================================"
    echo "Enter your complex problem (reasoning, coding, math, etc.)."
    echo "Type your input, then press Ctrl+D (or Ctrl+C to cancel)."
    echo "----------------------------------------------------------------------"
    PROBLEM=$(cat)
    if [ -z "$PROBLEM" ]; then
        echo "❌ No problem provided. Exiting."
        exit 1
    fi
    echo ""
    echo "📋 Problem received:"
    echo "$PROBLEM"
    echo "======================================================================"
}

# --- SETUP WORKSPACE ----------------------------------------------------------
setup_workspace() {
    if [ ! -d "$WORKSPACE_BASE" ]; then
        mkdir -p "$WORKSPACE_BASE" || {
            echo "❌ ERROR: Cannot create workspace base: $WORKSPACE_BASE"
            exit 1
        }
    fi

    local attempts=0
    while [ $attempts -lt 3 ]; do
        GEN_HASH=$((RANDOM % 900000 + 100000))
        TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
        WORKSPACE_DIR="${WORKSPACE_BASE}/TRT_${GEN_HASH}_${TIMESTAMP}"
        if mkdir -p "$WORKSPACE_DIR" 2>/dev/null; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    if [ ! -d "$WORKSPACE_DIR" ]; then
        echo "❌ ERROR: Failed to create unique workspace directory after 3 attempts."
        exit 1
    fi

    LOG_FILE="$WORKSPACE_DIR/trt_loop.log"
    STATE_FILE="$WORKSPACE_DIR/state.json"
    touch "$LOG_FILE" || {
        echo "❌ ERROR: Cannot create log file at $LOG_FILE"
        exit 1
    }
    echo "[$(date)] TRT Loop started. Model: $MODEL_NAME" >> "$LOG_FILE"
    echo "📁 Workspace: $WORKSPACE_DIR"
    echo "📄 Final answer will be saved to: $OUTPUT_FILE"

    # Create subdirectories
    mkdir -p "$WORKSPACE_DIR/rounds"

    # Initial state JSON
    cat > "$STATE_FILE" <<EOF
{
  "problem": "$PROBLEM",
  "rounds": [],
  "best_answer": "",
  "knowledge_list": []
}
EOF

    # Git initialisation
    if command -v git >/dev/null; then
        cd "$WORKSPACE_DIR" || exit 1
        git init -q
        git config user.email "trt@local"
        git config user.name "TRT Loop"
        echo "# TRT Loop Workspace" > README.md
        echo "Problem: $PROBLEM" >> README.md
        echo "Started: $(date)" >> README.md
        git add README.md
        git commit -q -m "Initial commit"
        echo "✅ Git repository ready"
        if [ "$AUTO_PUSH" = "true" ]; then
            if git remote get-url origin >/dev/null 2>&1; then
                echo "🔗 Remote origin already configured."
            else
                echo "⚠️  AUTO_PUSH is enabled but no remote set. Add with: git remote add origin <url>"
                AUTO_PUSH="false"
            fi
        fi
        cd - > /dev/null || exit 1
    fi
}

# --- GIT COMMIT ---------------------------------------------------------------
git_commit() {
    if ! command -v git >/dev/null; then return; fi
    cd "$WORKSPACE_DIR" || return
    git add .
    local msg="Round $ROUND_COUNT - $(date '+%H:%M:%S')"
    if git commit -q -m "$msg"; then
        echo "📦 Committed: $msg"
        if [ "$AUTO_PUSH" = "true" ] && git remote | grep -q origin; then
            git push -q origin main 2>/dev/null || git push -q origin master 2>/dev/null && echo "🚀 Pushed to remote"
        fi
    fi
    cd - > /dev/null || return
}

# --- OLLAMA REQUEST (with retries and timeout) --------------------------------
ask_ollama() {
    local sys_prompt="$1"
    local user_prompt="$2"
    local full="${sys_prompt}\n\nUser: ${user_prompt}"

    local payload
    payload=$(jq -n \
        --arg model "$MODEL_NAME" \
        --arg prompt "$full" \
        '{model: $model, prompt: $prompt, stream: false}')

    local response exit_code attempt=1 delay=$CURL_RETRY_DELAY
    while [ $attempt -le $CURL_RETRIES ]; do
        response=$(curl -s --max-time "$OLLAMA_MAX_TIMEOUT" --connect-timeout 60 \
            -X POST "$OLLAMA_URL" \
            -H "Content-Type: application/json" \
            -d "$payload" 2>/dev/null)
        exit_code=$?
        if [ $exit_code -eq 0 ] && [ -n "$response" ]; then
            break
        fi
        echo "⚠️  Ollama request failed (attempt $attempt/$CURL_RETRIES, exit $exit_code). Retrying in ${delay}s..." >&2
        sleep "$delay"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done

    if [ -z "$response" ] || [ $exit_code -ne 0 ]; then
        echo "⚠️  Ollama request failed after $CURL_RETRIES attempts." >&2
        return 1
    fi

    local result
    result=$(echo "$response" | jq -r '.response' 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        echo "⚠️  Failed to parse JSON response (jq error)." >&2
        echo "Raw response: $response" >> "$LOG_FILE"
        return 1
    fi
    echo "$result"
    return 0
}

# --- BUILD PROMPTS ------------------------------------------------------------
build_system_prompt() {
    cat <<EOF
You are an expert problem solver engaged in a recursive thinking process.
You will receive a complex problem, a previous best answer (if any), and a list of
negative constraints – things that previous answers failed to address or got wrong.

Your task:
1. Generate a new answer that improves upon the previous best while strictly avoiding all listed constraints.
2. Reflect on your new answer: identify any remaining weaknesses, assumptions, or potential errors.
3. Update the negative constraints list by adding new items that should be avoided in future iterations.

Output your response as a single JSON object with the following keys:
- "new_answer": a string containing your improved answer.
- "updated_constraints": an array of strings representing the updated list of constraints.

Do not include any extra text, markdown, or commentary outside the JSON.
EOF
}

build_user_prompt() {
    local problem="$1"
    local prev_answer="$2"
    local knowledge="$3"
    cat <<EOF
Problem:
$problem

Previous best answer:
$prev_answer

Current negative constraints (JSON array):
$knowledge

Please produce your JSON output.
EOF
}

# --- MAIN TRT ROUND -----------------------------------------------------------
run_round() {
    ((ROUND_COUNT++))
    echo -e "\n----------------------------------------------------------------------"
    echo "🧠 TRT ROUND #$ROUND_COUNT"
    echo "----------------------------------------------------------------------"

    # Load current state
    if [ -f "$STATE_FILE" ]; then
        local state_json
        state_json=$(cat "$STATE_FILE")
        BEST_ANSWER=$(echo "$state_json" | jq -r '.best_answer')
        KNOWLEDGE_LIST=$(echo "$state_json" | jq -c '.knowledge_list')
        # If best_answer is null or empty, set to empty string
        [ "$BEST_ANSWER" = "null" ] && BEST_ANSWER=""
    else
        BEST_ANSWER=""
        KNOWLEDGE_LIST="[]"
    fi

    # Build prompts
    SYSTEM_PROMPT=$(build_system_prompt)
    USER_PROMPT=$(build_user_prompt "$PROBLEM" "$BEST_ANSWER" "$KNOWLEDGE_LIST")

    echo "🤖 Consulting Ollama for recursive thinking..."
    local response
    response=$(ask_ollama "$SYSTEM_PROMPT" "$USER_PROMPT")
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        echo "❌ Failed to get response from Ollama. Skipping round."
        return 1
    fi

    # Extract JSON (robustly)
    local clean_json
    clean_json=$(echo "$response" | sed -n '/{/,/}/p' | tr -d '\n' | tr -s ' ')
    if ! echo "$clean_json" | jq empty >/dev/null 2>&1; then
        echo "❌ Invalid JSON generated. Skipping round."
        echo "Raw response (first 200 chars): ${response:0:200}..." >> "$LOG_FILE"
        return 1
    fi

    # Parse new_answer and updated_constraints
    local new_answer
    local updated_constraints
    new_answer=$(echo "$clean_json" | jq -r '.new_answer')
    updated_constraints=$(echo "$clean_json" | jq -c '.updated_constraints')

    # Validate fields
    if [ "$new_answer" = "null" ] || [ -z "$new_answer" ]; then
        echo "❌ Missing 'new_answer' in JSON. Skipping round."
        return 1
    fi
    if [ "$updated_constraints" = "null" ]; then
        updated_constraints="[]"
    fi

    # Update state
    BEST_ANSWER="$new_answer"
    KNOWLEDGE_LIST="$updated_constraints"

    # Save state
    local round_entry
    round_entry=$(jq -n \
        --arg round "$ROUND_COUNT" \
        --arg answer "$new_answer" \
        --argjson constraints "$updated_constraints" \
        '{round: $round | tonumber, answer: $answer, constraints: $constraints}')
    
    # Update state file: append round, update best_answer and knowledge_list
    local tmp_state
    tmp_state=$(mktemp)
    jq --argjson entry "$round_entry" \
       --arg best "$BEST_ANSWER" \
       --argjson kl "$KNOWLEDGE_LIST" \
       '.rounds += [$entry] | .best_answer = $best | .knowledge_list = $kl' \
       "$STATE_FILE" > "$tmp_state" && mv "$tmp_state" "$STATE_FILE"
    rm -f "$tmp_state"

    echo "✅ Answer updated and constraints list refreshed."
    echo "📝 New best answer (first 200 chars): ${BEST_ANSWER:0:200}..."
    echo "📋 Updated constraints: $KNOWLEDGE_LIST"

    # Save round transcript
    echo "--- Round $ROUND_COUNT ---" >> "$LOG_FILE"
    echo "Answer: $BEST_ANSWER" >> "$LOG_FILE"
    echo "Constraints: $KNOWLEDGE_LIST" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    # Archive round output
    echo "$clean_json" > "$WORKSPACE_DIR/rounds/round_${ROUND_COUNT}.json"

    return 0
}

# --- CLEANUP ------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    # Write final answer to output file
    if [ -n "$BEST_ANSWER" ] && [ "$BEST_ANSWER" != "null" ]; then
        echo "$BEST_ANSWER" > "$OUTPUT_FILE"
        echo "📄 Final answer saved to $OUTPUT_FILE"
    else
        echo "⚠️  No valid answer generated. Final output not written."
    fi

    if [ "$CLEAN_WORKSPACE" = "true" ] && [ -n "$WORKSPACE_DIR" ] && [ -d "$WORKSPACE_DIR" ]; then
        rm -rf "$WORKSPACE_DIR"
        echo "🧹 Workspace cleaned."
    fi
    echo -e "\n🛑 TRT Loop stopped after $ROUND_COUNT rounds."
    exit $exit_code
}
trap cleanup SIGINT SIGTERM

# --- MAIN ---------------------------------------------------------------------
main() {
    # Parse optional max_rounds
    if [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]; then
        MAX_ROUNDS="$1"
        echo "🔢 Will run for $MAX_ROUNDS rounds."
    fi

    check_ollama
    gather_user_input
    setup_workspace

    echo "======================================================================"
    echo "🚀 TRT Loop is running. Press Ctrl+C to stop."
    echo "   📂 Workspace: $WORKSPACE_DIR"
    echo "   📄 State file: $STATE_FILE"
    echo "   📄 Final answer: $OUTPUT_FILE"
    echo "   ⏳ Ollama timeout: ${OLLAMA_MAX_TIMEOUT}s (0 = infinite)"
    echo "   🔁 Curl retries: $CURL_RETRIES"
    if [ "$MAX_ROUNDS" -gt 0 ]; then
        echo "   🔢 Will stop after $MAX_ROUNDS rounds."
    else
        echo "   🔄 Will run indefinitely."
    fi
    echo "======================================================================"

    while true; do
        if [ "$MAX_ROUNDS" -gt 0 ] && [ "$ROUND_COUNT" -ge "$MAX_ROUNDS" ]; then
            echo "✅ Reached maximum rounds ($MAX_ROUNDS). Exiting."
            break
        fi

        run_round
        git_commit
        sleep 5
    done
    cleanup
}

# --- RUN ----------------------------------------------------------------------
main "$@"
