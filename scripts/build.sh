#!/bin/bash

# This script lives in scripts/ — change to project root so docker compose
# finds docker-compose.yml without needing an explicit -f flag everywhere.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Main script
print_header "vLLM with DeepGEMM Build Helper"

# Check if docker compose is installed
if ! command -v docker &> /dev/null || ! docker compose version > /dev/null 2>&1; then
    print_error "docker compose is not installed"
    exit 1
fi
print_success "docker compose found"

# Validate configuration
print_header "Step 1: Validating Configuration"
if docker compose config > /dev/null 2>&1; then
    print_success "docker compose.yml is valid"
else
    print_error "docker compose.yml has errors"
    exit 1
fi

# Ask user what they want to do
print_header "Step 2: Build Options"
echo "What would you like to do?"
echo "1) Build image (standard)"
echo "2) Build image (no cache - forces full rebuild)"
echo "3) Build and start services"
echo "4) Build, start, and show logs"
echo "5) Just start services (skip build)"
echo "6) Stop all services"
read -p "Enter choice [1-6]: " choice

case $choice in
    1)
        print_header "Building Image"
        if docker compose build; then
            print_success "Build completed"
        else
            print_error "Build failed"
            exit 1
        fi
        ;;
    2)
        print_header "Building Image (No Cache)"
        if docker compose build --no-cache; then
            print_success "Build completed"
        else
            print_error "Build failed"
            exit 1
        fi
        ;;
    3)
        print_header "Building Image"
        if docker compose build; then
            print_success "Build completed"
            print_header "Starting Services"
            if docker compose up -d; then
                print_success "Services started"
                sleep 5
                docker compose ps
            else
                print_error "Failed to start services"
                exit 1
            fi
        else
            print_error "Build failed"
            exit 1
        fi
        ;;
    4)
        print_header "Building Image"
        if docker compose build; then
            print_success "Build completed"
            print_header "Starting Services"
            if docker compose up -d; then
                print_success "Services started"
                sleep 5
                print_header "Container Logs (Ctrl+C to stop)"
                docker logs -f vllm-container
            else
                print_error "Failed to start services"
                exit 1
            fi
        else
            print_error "Build failed"
            exit 1
        fi
        ;;
    5)
        print_header "Starting Services"
        if docker compose up -d; then
            print_success "Services started"
            docker compose ps
        else
            print_error "Failed to start services"
            exit 1
        fi
        ;;
    6)
        print_header "Stopping Services"
        if docker compose down; then
            print_success "Services stopped"
        else
            print_error "Failed to stop services"
            exit 1
        fi
        ;;
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac

# Function to extract container information from docker-compose.yml
get_container_info() {
    local service=$1
    docker compose config | grep -A 10 "^  $service:" | grep "container_name:" | awk '{print $2}' | tr -d "'" 2>/dev/null
}

# Function to extract port information
get_service_port() {
    local service=$1
    docker compose config | grep -A 20 "^  $service:" | grep -m 1 "- \".*:.*\"" | grep -oE '[0-9]+:' | head -1 | tr -d ':' 2>/dev/null
}

# Extract container names dynamically from docker-compose.yml
VLLM_CONTAINER=$(get_container_info "vllm-node")
LITELLM_CONTAINER=$(get_container_info "litellm")
DB_CONTAINER=$(get_container_info "db")

# Extract ports
VLLM_PORT=$(docker compose config | grep -A 20 "vllm-node:" | grep -m 1 "\".*:.*\"" | grep -oE '[0-9]+:[0-9]+' | cut -d: -f1)
LITELLM_PORT=$(docker compose config | grep -A 20 "litellm:" | grep -m 1 "\".*:.*\"" | grep -oE '[0-9]+:[0-9]+' | cut -d: -f1)

# Set defaults if extraction failed
VLLM_CONTAINER="${VLLM_CONTAINER:-vllm-container}"
LITELLM_CONTAINER="${LITELLM_CONTAINER:-litellm}"
DB_CONTAINER="${DB_CONTAINER:-litellm_db}"
VLLM_PORT="${VLLM_PORT:-8000}"
LITELLM_PORT="${LITELLM_PORT:-4000}"

print_header "Additional Commands"
echo -e "${YELLOW}Dynamically generated from docker-compose.yml:${NC}"
echo ""
echo "${GREEN}Service Status:${NC}"
echo "  Check all:      docker compose ps"
echo ""
echo "${GREEN}View Logs:${NC}"
echo "  vLLM logs:      docker logs -f $VLLM_CONTAINER"
echo "  LiteLLM logs:   docker logs -f $LITELLM_CONTAINER"
echo "  Database logs:  docker logs -f $DB_CONTAINER"
echo ""
echo "${GREEN}Management:${NC}"
echo "  Stop services:  docker compose down"
echo "  Restart all:    docker compose restart"
echo ""
echo "${GREEN}vLLM Service ($VLLM_CONTAINER):${NC}"
echo "  View GPU stats: docker exec $VLLM_CONTAINER nvidia-smi"
echo "  Test API:       curl http://localhost:$VLLM_PORT/v1/models"
echo ""
echo "${GREEN}LiteLLM Service ($LITELLM_CONTAINER):${NC}"
echo "  Test health:    curl http://localhost:$LITELLM_PORT/health/liveliness"
echo "  View config:    docker exec $LITELLM_CONTAINER cat /app/generated_configs/config.yaml"
echo ""
echo "${GREEN}Database Service ($DB_CONTAINER):${NC}"
echo "  Connect to DB:  docker exec -it $DB_CONTAINER psql -d litellm -U llmproxy"
echo ""
