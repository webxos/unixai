#!/bin/bash
# ==============================================================================
# AGENT SPIN – Autonomous Code Factory (Ultimate Production Version)
# ==============================================================================
# Usage: bash agent_spin.sh ["your goal"] [max_cycles]
#
# Configuration (edit these variables):
#   MODEL_NAME            - Ollama model (e.g., qwen2.5:0.5b)
#   MAX_TEST_RETRIES      - fix attempts per cycle (0 = run tests once, no retries)
#   TEST_TIMEOUT          - seconds to wait for tests before killing (0 = no timeout)
#   OLLAMA_MAX_TIMEOUT    - max seconds for Ollama generation (0 = infinite)
#   AUTO_PUSH             - set to "true" to enable automatic git push
#   WORKSPACE_BASE        - where to create workspace (default: ~/Desktop)
#   MAX_CYCLES            - stop after this many cycles (0 = infinite)
#   CLEAN_NODE_MODULES    - remove node_modules folder after each cycle (default: false)
#   CURL_RETRIES          - number of retries for Ollama requests (default: 3)
#   CURL_RETRY_DELAY      - initial delay in seconds between retries (default: 2)
# ==============================================================================

# --- CONFIGURATION ------------------------------------------------------------
OLLAMA_URL="http://localhost:11434/api/generate"
MODEL_NAME="qwen2.5:0.5b"
MAX_TEST_RETRIES=3
TEST_TIMEOUT=60                     # set to 0 to disable timeout
OLLAMA_MAX_TIMEOUT=6000             # set to 0 for infinite
AUTO_PUSH="false"
WORKSPACE_BASE="${HOME}/Desktop"
MAX_CYCLES=0                        # 0 = infinite
CLEAN_NODE_MODULES="false"
CURL_RETRIES=3                      # number of retries for curl requests
CURL_RETRY_DELAY=2                  # initial delay (exponential backoff)

# --- INTERNAL VARIABLES -------------------------------------------------------
CYCLE_COUNT=0
USER_GOAL=""
WORKSPACE_DIR=""
LOG_FILE=""
PROJ_LANG=""
PROJ_NAME=""
PROJ_DIR=""
APP_FILE=""
TEST_FILE=""
TEST_CMD=""
RUN_CMD=""

# --- REQUIRE jq and timeout ---------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
    echo "❌ ERROR: 'jq' is required for JSON parsing. Please install it:"
    echo "   sudo apt install jq   (Debian/Ubuntu)"
    echo "   brew install jq       (macOS)"
    exit 1
fi

if ! command -v timeout >/dev/null 2>&1; then
    echo "❌ ERROR: 'timeout' command is required (GNU coreutils)."
    echo "   Please install coreutils or ensure 'timeout' is in PATH."
    exit 1
fi

# --- Cleanup on exit (guard against unset WORKSPACE_DIR) ----------------------
cleanup() {
    local exit_code=$?
    # Remove any leftover .tmp files only if WORKSPACE_DIR is set
    if [ -n "$WORKSPACE_DIR" ] && [ -d "$WORKSPACE_DIR" ]; then
        find "$WORKSPACE_DIR" -name "*.tmp" -type f -delete 2>/dev/null
    fi
    echo -e "\n🛑 AGENT SPIN stopped after $CYCLE_COUNT cycles."
    exit $exit_code
}
trap cleanup SIGINT SIGTERM

# --- Check Ollama & model -----------------------------------------------------
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
        echo "❌ ERROR: Ollama did not return a valid response. Maybe model '$MODEL_NAME' not found?" >&2
        exit 1
    fi
    echo "✅ Ollama ready (model: $MODEL_NAME)"
}

# --- Setup workspace ----------------------------------------------------------
setup_workspace() {
    if [ -z "$WORKSPACE_BASE" ] || [ ! -d "$WORKSPACE_BASE" ]; then
        WORKSPACE_BASE="$HOME"
        echo "⚠️  Desktop not found – using $HOME as base"
    fi

    if [ ! -w "$WORKSPACE_BASE" ]; then
        echo "❌ ERROR: Cannot write to $WORKSPACE_BASE. Please set WORKSPACE_BASE to a writable directory."
        exit 1
    fi

    local attempts=0
    while [ $attempts -lt 3 ]; do
        GEN_HASH=$((RANDOM % 900000 + 100000))
        TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
        WORKSPACE_DIR="${WORKSPACE_BASE}/AGENT_FORGE_${GEN_HASH}_${TIMESTAMP}"
        if mkdir -p "$WORKSPACE_DIR" 2>/dev/null; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    if [ ! -d "$WORKSPACE_DIR" ]; then
        echo "❌ ERROR: Cannot create workspace directory. Check permissions and disk space."
        exit 1
    fi

    LOG_FILE="$WORKSPACE_DIR/agent.log"
    touch "$LOG_FILE"
    echo "[$(date)] AGENT SPIN started. Model: $MODEL_NAME, Goal: $USER_GOAL" >> "$LOG_FILE"
    echo "📁 Workspace: $WORKSPACE_DIR"
    echo "💡 Goal: $USER_GOAL"

    if command -v git >/dev/null; then
        echo "🔧 Initializing Git repository..."
        cd "$WORKSPACE_DIR" || { echo "ERROR: cannot cd to workspace"; exit 1; }
        git init -q
        git config user.email "agent@spin.local"
        git config user.name "AGENT SPIN"
        echo "# AGENT SPIN Workspace" > README.md
        echo "Goal: $USER_GOAL" >> README.md
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
    else
        echo "⚠️  Git not found – skipping version control."
    fi
}

# --- Git commit after each cycle ----------------------------------------------
git_commit() {
    if ! command -v git >/dev/null; then
        return
    fi
    cd "$WORKSPACE_DIR" || return
    git add .
    local msg="Cycle $CYCLE_COUNT: $PROJ_LANG - $(basename "$PROJ_DIR")"
    if git commit -q -m "$msg"; then
        echo "📦 Committed: $msg"
        if [ "$AUTO_PUSH" = "true" ]; then
            if git remote | grep -q origin; then
                if git push -q origin main 2>/dev/null || git push -q origin master 2>/dev/null; then
                    echo "🚀 Pushed to remote"
                else
                    echo "⚠️  Push failed"
                fi
            fi
        fi
    else
        :
    fi
    cd - > /dev/null || return
}

# --- Safe JSON query to Ollama with retries ------------------------------------
ask_ollama() {
    local sys_prompt="$1"
    local user_prompt="$2"
    local full="${sys_prompt}\n\nUser: ${user_prompt}"

    local payload
    payload=$(jq -n \
        --arg model "$MODEL_NAME" \
        --arg prompt "$full" \
        '{model: $model, prompt: $prompt, stream: false}')

    local response
    local exit_code
    local attempt=1
    local delay=$CURL_RETRY_DELAY

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

# --- Check syntax and capture errors ------------------------------------------
check_syntax() {
    local file="$1"
    local lang="$2"
    local error_output
    case "$lang" in
        python)
            error_output=$(python3 -m py_compile "$file" 2>&1)
            ;;
        nodejs)
            error_output=$(node --check "$file" 2>&1)
            ;;
        bash)
            error_output=$(bash -n "$file" 2>&1)
            ;;
        *)
            return 0
    esac
    if [ $? -eq 0 ]; then
        return 0
    else
        echo "$error_output"
        return 1
    fi
}

# --- Fix a code file ----------------------------------------------------------
fix_code() {
    local file="$1"
    local lang="$2"
    local error_log="$3"
    local description="$4"

    local code
    code=$(cat "$file" 2>/dev/null)
    if [ -z "$code" ]; then
        echo "❌ Cannot read file: $file" >&2
        return 1
    fi

    local fix_prompt="You are a debugger. Fix the $description code below so it compiles and runs correctly. Output only the fixed source code, no markdown.\n\nLanguage: $lang\n\nCode:\n$code\n\nErrors:\n$error_log"
    if ask_ollama "You are an expert programmer. Fix the code." "$fix_prompt" > "$file.tmp"; then
        if [ -s "$file.tmp" ]; then
            mv "$file.tmp" "$file"
            [ "$lang" = "bash" ] && chmod +x "$file"
            local syntax_result
            syntax_result=$(check_syntax "$file" "$lang")
            if [ $? -eq 0 ]; then
                return 0
            else
                echo "⚠️  Fixed code still has syntax errors: $syntax_result" >&2
                return 1
            fi
        else
            echo "⚠️  Fix attempt produced empty file." >&2
            rm -f "$file.tmp"
            return 1
        fi
    else
        rm -f "$file.tmp"
        return 1
    fi
}

# --- Main loop phases ---------------------------------------------------------
ideate() {
    ((CYCLE_COUNT++))
    echo -e "\n----------------------------------------------------------------------"
    echo "🔄 CYCLE #$CYCLE_COUNT"
    echo "----------------------------------------------------------------------"

    local lang_choice
    lang_choice=$(ask_ollama \
        "You are a software architect. Output only one word: python, nodejs, or bash." \
        "For goal: '$USER_GOAL', which runtime should I use?")
    if [ $? -ne 0 ] || [ -z "$lang_choice" ]; then
        PROJ_LANG="${PROJ_LANG:-bash}"
        echo "⚠️  Using fallback language: $PROJ_LANG"
    else
        local matched
        matched=$(echo "$lang_choice" | grep -Eio 'python|nodejs|bash' | head -n1)
        if [ -n "$matched" ]; then
            PROJ_LANG=$(echo "$matched" | tr '[:upper:]' '[:lower:]')
        else
            PROJ_LANG="bash"
            echo "⚠️  Could not detect language – falling back to bash"
        fi
    fi

    PROJ_NAME="Cycle_${CYCLE_COUNT}_${PROJ_LANG}"
    PROJ_DIR="$WORKSPACE_DIR/$PROJ_NAME"
    if ! mkdir -p "$PROJ_DIR"; then
        echo "❌ ERROR: cannot create project directory: $PROJ_DIR"
        return 1
    fi
    echo "📦 Project: $PROJ_NAME  |  Runtime: $PROJ_LANG"
    echo "📂 Location: $PROJ_DIR"

    case "$PROJ_LANG" in
        python)
            APP_FILE="app.py"
            TEST_FILE="test_app.py"
            TEST_CMD="python3 $TEST_FILE"
            RUN_CMD="python3 $APP_FILE"
            ;;
        nodejs)
            APP_FILE="app.js"
            TEST_FILE="test_app.js"
            TEST_CMD="node $TEST_FILE"
            RUN_CMD="node $APP_FILE"
            ;;
        *)
            APP_FILE="app.sh"
            TEST_FILE="test_app.sh"
            TEST_CMD="./$TEST_FILE"
            RUN_CMD="./$APP_FILE"
            ;;
    esac
    return 0
}

build() {
    echo "🤖 Generating code (may take a while) ..."
    cd "$PROJ_DIR" || { echo "❌ ERROR: cannot cd to $PROJ_DIR"; return 1; }

    local sys="Output only raw source code. No markdown, no explanations."

    if ! ask_ollama "$sys" "Write a $PROJ_LANG script for: $USER_GOAL" > "$APP_FILE"; then
        echo "❌ ERROR: failed to generate app code."
        return 1
    fi
    if [ ! -s "$APP_FILE" ]; then
        echo "❌ ERROR: generated app file is empty."
        return 1
    fi

    if ! ask_ollama "$sys" "Write a test script named $TEST_FILE that validates $APP_FILE" > "$TEST_FILE"; then
        echo "❌ ERROR: failed to generate test code."
        return 1
    fi
    if [ ! -s "$TEST_FILE" ]; then
        echo "❌ ERROR: generated test file is empty."
        return 1
    fi

    if [ "$PROJ_LANG" = "bash" ]; then
        chmod +x "$APP_FILE" "$TEST_FILE"
    fi

    cd - > /dev/null || return 1
    return 0
}

test_and_fix() {
    echo "🧪 Testing..."
    cd "$PROJ_DIR" || { echo "❌ ERROR: cannot cd to $PROJ_DIR"; return 1; }

    local attempts=0
    local status=1

    # --- Pre‑test syntax fixing (using actual error output) ---
    echo "🔍 Checking syntax..."
    for file in "$APP_FILE" "$TEST_FILE"; do
        local syntax_errors
        syntax_errors=$(check_syntax "$file" "$PROJ_LANG")
        if [ $? -ne 0 ]; then
            echo "⚠️  Syntax errors in $file – attempting to fix."
            if fix_code "$file" "$PROJ_LANG" "$syntax_errors" "$(basename "$file")"; then
                echo "✅ $file fixed."
            else
                echo "❌ Could not fix $file – will try during test loop."
            fi
        fi
    done

    # --- Main test loop (runs at least once, retries up to MAX_TEST_RETRIES) ---
    # Condition: while attempts <= MAX_TEST_RETRIES and status != 0
    while [ $attempts -le $MAX_TEST_RETRIES ] && [ $status -ne 0 ]; do
        ((attempts++))
        echo "🔍 [Attempt $attempts/$((MAX_TEST_RETRIES + 1))] Running: $TEST_CMD"

        if [ "$TEST_TIMEOUT" -gt 0 ]; then
            timeout "$TEST_TIMEOUT" bash -c "$TEST_CMD" > test_output.log 2>&1
            status=$?
            if [ $status -eq 124 ]; then
                echo "⏱️  Test timed out after ${TEST_TIMEOUT}s – treating as failure."
                status=1
            fi
        else
            bash -c "$TEST_CMD" > test_output.log 2>&1
            status=$?
        fi

        if [ $status -eq 0 ]; then
            echo "✅ SUCCESS"
            echo "[$(date)] Cycle $CYCLE_COUNT passed" >> "$LOG_FILE"
            break
        elif [ $attempts -le $MAX_TEST_RETRIES ]; then
            echo "🔧 Diagnosing and fixing..."
            local errors
            errors=$(cat test_output.log 2>/dev/null)

            local fixed_ok=0
            echo "   → Attempting to fix test file..."
            if fix_code "$TEST_FILE" "$PROJ_LANG" "$errors" "test file"; then
                fixed_ok=1
                echo "   ✅ Test file fixed."
            else
                echo "   ⚠️  Could not fix test file – will fix app instead."
                echo "   → Attempting to fix application code..."
                if fix_code "$APP_FILE" "$PROJ_LANG" "$errors" "application"; then
                    fixed_ok=1
                    echo "   ✅ Application fixed."
                else
                    echo "   ❌ Could not fix either file – skipping to next attempt."
                fi
            fi

            if [ $fixed_ok -eq 1 ]; then
                for file in "$APP_FILE" "$TEST_FILE"; do
                    local syntax_errors
                    syntax_errors=$(check_syntax "$file" "$PROJ_LANG")
                    if [ $? -ne 0 ]; then
                        echo "⚠️  $file still has syntax errors: $syntax_errors"
                    fi
                done
            fi
        fi
    done

    if [ $status -ne 0 ]; then
        echo "❌ FAILED after $((attempts - 1)) attempts"   # adjusted count
        echo "[$(date)] Cycle $CYCLE_COUNT failed" >> "$LOG_FILE"
    fi
    cd - > /dev/null || return 1
    return $status
}

cleanup_cycle() {
    cd "$PROJ_DIR" 2>/dev/null || return
    rm -f test_output.log
    if [ "$CLEAN_NODE_MODULES" = "true" ]; then
        rm -rf node_modules 2>/dev/null
    fi
    rm -rf __pycache__ *.pyc *.tmp 2>/dev/null
    cd - > /dev/null || return
    sleep 0.5
}

# --- Main ---------------------------------------------------------------------
main() {
    if [ -n "$1" ]; then
        USER_GOAL="$1"
    else
        echo "======================================================================"
        echo "🌀 AGENT SPIN (Model: $MODEL_NAME)"
        echo "======================================================================"
        echo "💡 What should I build for you?"
        echo -n "> "
        read -r USER_GOAL
        if [ -z "$USER_GOAL" ]; then
            USER_GOAL="Automated file processing framework with comprehensive tests"
            echo "   Using default goal: $USER_GOAL"
        fi
    fi

    if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -gt 0 ]; then
        MAX_CYCLES="$2"
        echo "🔢 Will run for $MAX_CYCLES cycles."
    fi

    check_ollama
    setup_workspace

    echo "======================================================================"
    echo "🚀 Running forever. Press Ctrl+C to stop."
    echo "   Each cycle creates a new folder – nothing is ever deleted."
    echo "   ⏳ Ollama generation timeout: ${OLLAMA_MAX_TIMEOUT}s (0 = infinite)"
    echo "   🧪 Test timeout: ${TEST_TIMEOUT}s per run (0 = no timeout)"
    echo "   🔁 Curl retries: $CURL_RETRIES"
    if [ "$MAX_CYCLES" -gt 0 ]; then
        echo "   🔢 Will stop after $MAX_CYCLES cycles."
    fi
    echo "======================================================================"

    while true; do
        if [ "$MAX_CYCLES" -gt 0 ] && [ "$CYCLE_COUNT" -ge "$MAX_CYCLES" ]; then
            echo "✅ Reached maximum cycles ($MAX_CYCLES). Exiting."
            break
        fi

        if ! ideate; then
            echo "⚠️  Ideation failed – aborting cycle."
            sleep 5
            continue
        fi
        if ! build; then
            echo "⚠️  Build failed – aborting cycle."
            git_commit
            cleanup_cycle
            continue
        fi
        test_and_fix
        git_commit
        cleanup_cycle
    done
    cleanup
}

# --- Run ----------------------------------------------------------------------
main "$@"
