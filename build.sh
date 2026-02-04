#!/bin/bash

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

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    print_error "docker-compose is not installed"
    exit 1
fi
print_success "docker-compose found"

# Validate configuration
print_header "Step 1: Validating Configuration"
if docker-compose config --quiet; then
    print_success "docker-compose.yml is valid"
else
    print_error "docker-compose.yml has errors"
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
        docker-compose build
        print_success "Build completed"
        ;;
    2)
        print_header "Building Image (No Cache)"
        docker-compose build --no-cache
        print_success "Build completed"
        ;;
    3)
        print_header "Building Image"
        docker-compose build && print_success "Build completed"
        print_header "Starting Services"
        docker-compose up -d
        print_success "Services started"
        sleep 5
        docker-compose ps
        ;;
    4)
        print_header "Building Image"
        docker-compose build && print_success "Build completed"
        print_header "Starting Services"
        docker-compose up -d
        print_success "Services started"
        sleep 5
        print_header "Container Logs (Ctrl+C to stop)"
        docker logs -f vllm-container
        ;;
    5)
        print_header "Starting Services"
        docker-compose up -d
        print_success "Services started"
        docker-compose ps
        ;;
    6)
        print_header "Stopping Services"
        docker-compose down
        print_success "Services stopped"
        ;;
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac

print_header "Additional Commands"
echo "View logs:      docker logs -f vllm-container"
echo "Check status:   docker-compose ps"
echo "Stop services:  docker-compose down"
echo "View GPU stats: docker exec vllm-container nvidia-smi"
echo "Test API:       curl http://localhost:8000/v1/models"
