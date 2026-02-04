#!/bin/bash

###############################################################################
# LiteLLM + vLLM Test Script
# Tests both the LiteLLM proxy (with Anthropic API compatibility)
# and vLLM direct server with comprehensive test suites
###############################################################################

set -e

# Configuration
LITELLM_HOST="${LITELLM_HOST:-localhost}"
LITELLM_PORT="${LITELLM_PORT:-4000}"
LITELLM_URL="http://${LITELLM_HOST}:${LITELLM_PORT}"
VLLM_HOST="${VLLM_HOST:-localhost}"
VLLM_PORT="${VLLM_PORT:-8000}"
VLLM_URL="http://${VLLM_HOST}:${VLLM_PORT}"
API_KEY="${ANTHROPIC_AUTH_TOKEN:-sk-FAKE}"
MODEL="${MODEL:-glm47-flash}"
VLLM_MODEL="vllm_agent"  # Fixed model name for vLLM
MAX_TOKENS="${MAX_TOKENS:-512}"
TIMEOUT="${TIMEOUT:-30}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###############################################################################
# Helper Functions
###############################################################################

log_info() {
    echo -e "${BLUE}ℹ  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✓  $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠  $1${NC}"
}

log_error() {
    echo -e "${RED}✗  $1${NC}"
}

###############################################################################
# Health Check
###############################################################################

check_litellm_health() {
    log_info "Checking litellm proxy health at ${LITELLM_URL}..."

    if ! response=$(curl -s -m "$TIMEOUT" "${LITELLM_URL}/health/liveliness" 2>/dev/null); then
        log_error "Failed to connect to litellm proxy at ${LITELLM_URL}"
        log_info "Make sure the litellm proxy is running. Start it with: docker-compose up -d litellm"
        return 1
    fi

    if echo "$response" | grep -q "healthy\|ok\|running"; then
        log_success "LiteLLM proxy is healthy"
        return 0
    else
        log_warning "LiteLLM health response: $response"
        return 0  # Continue anyway, might still work
    fi
}

###############################################################################
# List Available Models
###############################################################################

list_models() {
    log_info "Fetching available models from litellm..."

    response=$(curl -s -m "$TIMEOUT" "${LITELLM_URL}/v1/models" \
        -H "Authorization: Bearer ${API_KEY}")

    if echo "$response" | jq . > /dev/null 2>&1; then
        log_success "Available models:"
        echo "$response" | jq -r '.data[] | "\(.id)"' | sed 's/^/  - /'
        return 0
    else
        log_warning "Could not parse models response: $response"
        return 1
    fi
}

###############################################################################
# Test 1: Basic Message API Call
###############################################################################

test_basic_message() {
    log_info "Test 1: Basic message API call"
    echo "  Model: ${MODEL}"
    echo "  Max Tokens: ${MAX_TOKENS}"

    response=$(curl -s -m "$TIMEOUT" "${LITELLM_URL}/v1/messages" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d '{
            "model": "'"anthropic/${MODEL}"'",
            "max_tokens": '"${MAX_TOKENS}"',
            "messages": [
                {"role": "user", "content": "Hello! Please respond with a brief greeting in 1-2 sentences."}
            ]
        }')

    if echo "$response" | jq . > /dev/null 2>&1; then
        log_success "Got valid JSON response"

        # Extract and display response
        content=$(echo "$response" | jq -r '.content[0].text // .error.message // "N/A"' 2>/dev/null)
        echo "  Response: ${content:0:200}"

        if echo "$response" | jq -e '.content' > /dev/null 2>&1; then
            log_success "Message API call succeeded"
            return 0
        else
            log_error "Response missing content field"
            echo "$response" | jq .
            return 1
        fi
    else
        log_error "Invalid JSON response"
        echo "  Response: $response"
        return 1
    fi
}

###############################################################################
# Test 2: Message with System Prompt
###############################################################################

test_system_prompt() {
    log_info "Test 2: Message with system prompt"

    response=$(curl -s -m "$TIMEOUT" "${LITELLM_URL}/v1/messages" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d '{
            "model": "'"anthropic/${MODEL}"'",
            "max_tokens": '"${MAX_TOKENS}"',
            "system": "You are a helpful assistant. Always be concise and clear.",
            "messages": [
                {"role": "user", "content": "What is 2+2?"}
            ]
        }')

    if echo "$response" | jq -e '.content' > /dev/null 2>&1; then
        content=$(echo "$response" | jq -r '.content[0].text // "N/A"' 2>/dev/null)
        echo "  Response: ${content:0:200}"
        log_success "System prompt test succeeded"
        return 0
    else
        log_error "System prompt test failed"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 1
    fi
}

###############################################################################
# Test 3: Multi-turn Conversation
###############################################################################

test_multi_turn() {
    log_info "Test 3: Multi-turn conversation"

    response=$(curl -s -m "$TIMEOUT" "${LITELLM_URL}/v1/messages" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d '{
            "model": "'"anthropic/${MODEL}"'",
            "max_tokens": '"${MAX_TOKENS}"',
            "messages": [
                {"role": "user", "content": "What is Python?"},
                {"role": "assistant", "content": "Python is a popular programming language known for its simplicity and versatility."},
                {"role": "user", "content": "Name three use cases."}
            ]
        }')

    if echo "$response" | jq -e '.content' > /dev/null 2>&1; then
        content=$(echo "$response" | jq -r '.content[0].text // "N/A"' 2>/dev/null)
        echo "  Response: ${content:0:200}"
        log_success "Multi-turn conversation test succeeded"
        return 0
    else
        log_error "Multi-turn conversation test failed"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 1
    fi
}

###############################################################################
# Test 4: Temperature and Sampling Parameters
###############################################################################

test_parameters() {
    log_info "Test 4: Temperature and sampling parameters"

    response=$(curl -s -m "$TIMEOUT" "${LITELLM_URL}/v1/messages" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d '{
            "model": "'"anthropic/${MODEL}"'",
            "max_tokens": '"${MAX_TOKENS}"',
            "temperature": 0.7,
            "top_p": 0.9,
            "messages": [
                {"role": "user", "content": "Tell me something interesting."}
            ]
        }')

    if echo "$response" | jq -e '.content' > /dev/null 2>&1; then
        content=$(echo "$response" | jq -r '.content[0].text // "N/A"' 2>/dev/null)
        echo "  Response: ${content:0:200}"
        log_success "Parameters test succeeded"
        return 0
    else
        log_error "Parameters test failed"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 1
    fi
}

###############################################################################
# Test 5: Streaming (if supported)
###############################################################################

test_streaming() {
    log_info "Test 5: Streaming API call"

    log_info "Sending streaming request..."
    response=$(curl -s -m "$TIMEOUT" "${LITELLM_URL}/v1/messages" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d '{
            "model": "'"anthropic/${MODEL}"'",
            "max_tokens": 256,
            "stream": true,
            "messages": [
                {"role": "user", "content": "Count to 5, each number on a new line."}
            ]
        }')

    # For streaming, we expect multiple SSE events
    if echo "$response" | grep -q "data:"; then
        log_success "Streaming response received"

        # Extract and display first few stream chunks
        echo "  First few chunks:"
        echo "$response" | grep "^data:" | head -3 | sed 's/^data: /    /'
        return 0
    else
        log_warning "No streaming data in response (may not be supported)"
        return 0
    fi
}

###############################################################################
# vLLM Direct Server Tests
###############################################################################

check_vllm_health() {
    log_info "Checking vLLM health at ${VLLM_URL}...\""

    if ! response=$(curl -s -m "$TIMEOUT" "${VLLM_URL}/health" 2>/dev/null); then
        log_error "Failed to connect to vLLM at ${VLLM_URL}"
        log_info "Make sure vLLM is running. Start it with: docker-compose up -d vllm"
        return 1
    fi

    if echo "$response" | grep -q "healthy\|ok\|running\|status"; then
        log_success "vLLM is healthy"
        return 0
    else
        log_warning "vLLM health response: $response"
        return 0
    fi
}

list_vllm_models() {
    log_info "Fetching available models from vLLM...\""

    response=$(curl -s -m "$TIMEOUT" "${VLLM_URL}/v1/models" \
        -H "Authorization: Bearer ${API_KEY}")

    if echo "$response" | jq . > /dev/null 2>&1; then
        log_success "Available models:"
        echo "$response" | jq -r '.data[] | "\(.id)"' | sed 's/^/  - /'
        return 0
    else
        log_warning "Could not parse models response: $response"
        return 1
    fi
}

test_vllm_basic_message() {
    log_info "Test 1: Basic message API call (vLLM)"
    echo "  Model: ${VLLM_MODEL}"
    echo "  Max Tokens: ${MAX_TOKENS}"

    response=$(curl -s -m "$TIMEOUT" "${VLLM_URL}/v1/messages" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d '{
            "model": "'"${VLLM_MODEL}"'",
            "max_tokens": '"${MAX_TOKENS}"',
            "messages": [
                {"role": "user", "content": "Hello! Please respond with a brief greeting in 1-2 sentences."}
            ]
        }')

    if echo "$response" | jq . > /dev/null 2>&1; then
        log_success "Got valid JSON response"

        # Extract and display response
        content=$(echo "$response" | jq -r '.content[0].text // .error.message // "N/A"' 2>/dev/null)
        echo "  Response: ${content:0:200}"

        if echo "$response" | jq -e '.content' > /dev/null 2>&1; then
            log_success "Message API call succeeded"
            return 0
        else
            log_error "Response missing content field"
            echo "$response" | jq .
            return 1
        fi
    else
        log_error "Invalid JSON response"
        echo "  Response: $response"
        return 1
    fi
}

test_vllm_system_prompt() {
    log_info "Test 2: Message with system prompt (vLLM)"

    response=$(curl -s -m "$TIMEOUT" "${VLLM_URL}/v1/messages" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d '{
            "model": "'"${VLLM_MODEL}"'",
            "max_tokens": '"${MAX_TOKENS}"',
            "system": "You are a helpful assistant. Always be concise and clear.",
            "messages": [
                {"role": "user", "content": "What is 2+2?"}
            ]
        }')

    if echo "$response" | jq -e '.content' > /dev/null 2>&1; then
        content=$(echo "$response" | jq -r '.content[0].text // "N/A"' 2>/dev/null)
        echo "  Response: ${content:0:200}"
        log_success "System prompt test succeeded"
        return 0
    else
        log_error "System prompt test failed"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 1
    fi
}

test_vllm_multi_turn() {
    log_info "Test 3: Multi-turn conversation (vLLM)"

    response=$(curl -s -m "$TIMEOUT" "${VLLM_URL}/v1/messages" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d '{
            "model": "'"${VLLM_MODEL}"'",
            "max_tokens": '"${MAX_TOKENS}"',
            "messages": [
                {"role": "user", "content": "What is Python?"},
                {"role": "assistant", "content": "Python is a popular programming language known for its simplicity and versatility."},
                {"role": "user", "content": "Name three use cases."}
            ]
        }')

    if echo "$response" | jq -e '.content' > /dev/null 2>&1; then
        content=$(echo "$response" | jq -r '.content[0].text // "N/A"' 2>/dev/null)
        echo "  Response: ${content:0:200}"
        log_success "Multi-turn conversation test succeeded"
        return 0
    else
        log_error "Multi-turn conversation test failed"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 1
    fi
}

test_vllm_parameters() {
    log_info "Test 4: Temperature and sampling parameters (vLLM)"

    response=$(curl -s -m "$TIMEOUT" "${VLLM_URL}/v1/messages" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d '{
            "model": "'"${VLLM_MODEL}"'",
            "max_tokens": '"${MAX_TOKENS}"',
            "temperature": 0.7,
            "top_p": 0.9,
            "messages": [
                {"role": "user", "content": "Tell me something interesting."}
            ]
        }')

    if echo "$response" | jq -e '.content' > /dev/null 2>&1; then
        content=$(echo "$response" | jq -r '.content[0].text // "N/A"' 2>/dev/null)
        echo "  Response: ${content:0:200}"
        log_success "Parameters test succeeded"
        return 0
    else
        log_error "Parameters test failed"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 1
    fi
}

###############################################################################
# Main Test Suite
###############################################################################

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           LiteLLM + vLLM Comprehensive Test Suite              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    # Initialize test counters
    total_tests_run=0
    total_tests_passed=0
    total_tests_failed=0

    ###########################################################################
    # LiteLLM Tests
    ###########################################################################

    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           LiteLLM Proxy - Anthropic API Tests                  ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    log_info "Configuration:"
    echo "  LiteLLM URL: ${LITELLM_URL}"
    echo "  Model: anthropic/${MODEL}"
    echo "  API Key: ${API_KEY:0:10}..."
    echo "  Max Tokens: ${MAX_TOKENS}"
    echo "  Timeout: ${TIMEOUT}s"
    echo ""

    # Initialize litellm test counters
    litellm_tests_run=0
    litellm_tests_passed=0
    litellm_tests_failed=0

    # Health check
    if ! check_litellm_health; then
        log_error "LiteLLM proxy is not accessible. Skipping LiteLLM tests."
        litellm_tests_failed=1
    else
        echo ""

        # List models
        echo ""
        if ! list_models; then
            log_warning "Could not fetch model list"
        fi
        echo ""

        # Run tests
        echo "════════════════════════════════════════════════════════════════"
        echo ""

        tests=("test_basic_message" "test_system_prompt" "test_multi_turn" "test_parameters" "test_streaming")

        for test in "${tests[@]}"; do
            ((litellm_tests_run++))
            echo ""
            if $test; then
                ((litellm_tests_passed++))
            else
                ((litellm_tests_failed++))
            fi
        done

        # LiteLLM Summary
        echo ""
        echo "════════════════════════════════════════════════════════════════"
        echo ""
        log_info "LiteLLM Test Summary:"
        echo "  Total: ${litellm_tests_run}"
        log_success "Passed: ${litellm_tests_passed}"
        if [ "$litellm_tests_failed" -gt 0 ]; then
            log_error "Failed: ${litellm_tests_failed}"
        fi
        echo ""
    fi

    total_tests_run=$((total_tests_run + litellm_tests_run))
    total_tests_passed=$((total_tests_passed + litellm_tests_passed))
    total_tests_failed=$((total_tests_failed + litellm_tests_failed))

    ###########################################################################
    # vLLM Direct Server Tests
    ###########################################################################

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           vLLM Direct Server Tests                             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    log_info "Configuration:"
    echo "  vLLM URL: ${VLLM_URL}"
    echo "  Model: ${VLLM_MODEL}"
    echo "  API Key: ${API_KEY:0:10}..."
    echo "  Max Tokens: ${MAX_TOKENS}"
    echo "  Timeout: ${TIMEOUT}s"
    echo ""

    # Initialize vllm test counters
    vllm_tests_run=0
    vllm_tests_passed=0
    vllm_tests_failed=0

    # Health check
    if ! check_vllm_health; then
        log_error "vLLM is not accessible. Skipping vLLM tests."
        vllm_tests_failed=1
    else
        echo ""

        # List models
        echo ""
        if ! list_vllm_models; then
            log_warning "Could not fetch model list"
        fi
        echo ""

        # Run tests
        echo "════════════════════════════════════════════════════════════════"
        echo ""

        vllm_tests=("test_vllm_basic_message" "test_vllm_system_prompt" "test_vllm_multi_turn" "test_vllm_parameters")

        for test in "${vllm_tests[@]}"; do
            ((vllm_tests_run++))
            echo ""
            if $test; then
                ((vllm_tests_passed++))
            else
                ((vllm_tests_failed++))
            fi
        done

        # vLLM Summary
        echo ""
        echo "════════════════════════════════════════════════════════════════"
        echo ""
        log_info "vLLM Test Summary:"
        echo "  Total: ${vllm_tests_run}"
        log_success "Passed: ${vllm_tests_passed}"
        if [ "$vllm_tests_failed" -gt 0 ]; then
            log_error "Failed: ${vllm_tests_failed}"
        fi
        echo ""
    fi

    total_tests_run=$((total_tests_run + vllm_tests_run))
    total_tests_passed=$((total_tests_passed + vllm_tests_passed))
    total_tests_failed=$((total_tests_failed + vllm_tests_failed))

    ###########################################################################
    # Overall Summary
    ###########################################################################

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                     Overall Test Summary                       ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Combined Results:"
    echo "  Total: ${total_tests_run}"
    log_success "Passed: ${total_tests_passed}"
    if [ "$total_tests_failed" -gt 0 ]; then
        log_error "Failed: ${total_tests_failed}"
    fi
    echo ""

    if [ "$total_tests_failed" -eq 0 ]; then
        log_success "All tests passed! ✓"
        echo ""
        return 0
    else
        log_error "Some tests failed"
        echo ""
        return 1
    fi
}

###############################################################################
# Script Entry Point
###############################################################################

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
