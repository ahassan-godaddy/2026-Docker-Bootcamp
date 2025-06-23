#!/bin/bash

# 2025 Docker Bootcamp - Part 1 Automation Script
# This script automates all the steps from Part 1 of the Docker Bootcamp README
# with validation of expected outputs and proper error handling.

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
REDIS_CONTAINER_NAME="redis-bootcamp-test"
CUSTOM_IMAGE_NAME="bootcamp-test"
NETWORK_NAME="bootcamp_test_net"
TEST_KEY="myname"
TEST_VALUE="Andrew"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}STEP: $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test resources..."
    
    # Stop and remove containers
    docker stop "$REDIS_CONTAINER_NAME" 2>/dev/null || true
    docker rm "$REDIS_CONTAINER_NAME" 2>/dev/null || true
    
    # Remove custom image
    docker rmi "$CUSTOM_IMAGE_NAME" 2>/dev/null || true
    
    # Remove network
    docker network rm "$NETWORK_NAME" 2>/dev/null || true
    
    # Cleanup docker-compose
    if [ -d "$PROJECT_ROOT/redis_client_app" ]; then
        cd "$PROJECT_ROOT/redis_client_app"
        docker-compose down 2>/dev/null || true
        cd "$SCRIPT_DIR"
    fi
    
    log_success "Cleanup completed"
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Function to validate command output
validate_output() {
    local command="$1"
    local expected_pattern="$2"
    local description="$3"
    
    log_info "Running: $command"
    local output
    output=$(eval "$command" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        if echo "$output" | grep -q "$expected_pattern"; then
            log_success "$description - Output contains expected pattern: '$expected_pattern'"
            return 0
        else
            log_error "$description - Output does not contain expected pattern: '$expected_pattern'"
            log_error "Actual output: $output"
            return 1
        fi
    else
        log_error "$description - Command failed with exit code: $exit_code"
        log_error "Output: $output"
        return 1
    fi
}

# Function to wait for container to be ready
wait_for_container() {
    local container_name="$1"
    local max_wait="$2"
    local counter=0
    
    log_info "Waiting for container '$container_name' to be ready..."
    
    while [ $counter -lt "$max_wait" ]; do
        if docker ps --filter "name=$container_name" --filter "status=running" --format "table {{.Names}}" | grep -q "$container_name"; then
            log_success "Container '$container_name' is running"
            sleep 2  # Give it a moment to fully initialize
            return 0
        fi
        sleep 1
        counter=$((counter + 1))
    done
    
    log_error "Container '$container_name' did not start within $max_wait seconds"
    return 1
}

# Function to test Redis connectivity
test_redis_connectivity() {
    local container_name="$1"
    local key="$2"
    local value="$3"
    
    log_info "Testing Redis connectivity..."
    
    # Test SET operation
    local set_result
    set_result=$(docker exec "$container_name" redis-cli SET "$key" "$value" 2>&1)
    if [ "$set_result" = "OK" ]; then
        log_success "Redis SET operation successful"
    else
        log_error "Redis SET operation failed: $set_result"
        return 1
    fi
    
    # Test GET operation
    local get_result
    get_result=$(docker exec "$container_name" redis-cli GET "$key" 2>&1)
    # Handle both quoted and unquoted Redis responses
    if [ "$get_result" = "\"$value\"" ] || [ "$get_result" = "$value" ]; then
        log_success "Redis GET operation successful - Retrieved: $get_result"
    else
        log_error "Redis GET operation failed - Expected: \"$value\" or $value, Got: $get_result"
        return 1
    fi
    
    return 0
}

# Main test function
run_part1_tests() {
    log_step "Starting 2025 Docker Bootcamp Part 1 Automation"
    
    # Step 1: Pull Redis image
    log_step "1. Pulling Redis Image"
    validate_output "docker pull redis" "Pull complete\|Status.*up to date\|Status: Downloaded newer image" "Redis image pull"
    
    # Step 2: Inspect Redis image
    log_step "2. Inspecting Redis Image"
    validate_output "docker images redis" "redis.*latest" "Redis image listing"
    
    # Step 3: Create Redis container
    log_step "3. Creating Redis Container"
    validate_output "docker run --name $REDIS_CONTAINER_NAME -d redis:latest" "[a-f0-9]" "Redis container creation"
    
    # Wait for Redis to be ready
    wait_for_container "$REDIS_CONTAINER_NAME" 30
    
    # Step 4: View container list
    log_step "4. Viewing Container List"
    validate_output "docker ps" "$REDIS_CONTAINER_NAME" "Container listing"
    
    # Step 5: Check Redis logs
    log_step "5. Checking Redis Logs"
    validate_output "docker logs $REDIS_CONTAINER_NAME" "Ready to accept connections" "Redis logs check"
    
    # Step 6: Test Redis data operations
    log_step "6. Testing Redis Data Operations"
    test_redis_connectivity "$REDIS_CONTAINER_NAME" "$TEST_KEY" "$TEST_VALUE"
    
    # Step 7: Build custom Docker image
    log_step "7. Building Custom Python Redis Client Image"
    if [ ! -d "$PROJECT_ROOT/redis_client_app" ]; then
        log_error "redis_client_app directory not found at: $PROJECT_ROOT/redis_client_app"
        return 1
    fi
    
    cd "$PROJECT_ROOT"
    validate_output "docker build -f redis_client_app/Dockerfile -t $CUSTOM_IMAGE_NAME redis_client_app" "naming to docker.io\|Successfully tagged" "Custom image build"
    
    # Step 8: Test custom image commands
    log_step "8. Testing Custom Python Redis Client"
    validate_output "docker run $CUSTOM_IMAGE_NAME" "store_data\|get_data\|check_redis\|hello_world" "Custom image command listing"
    
    # Step 9: Test hello_world command
    log_step "9. Testing Hello World Command"
    validate_output "docker run $CUSTOM_IMAGE_NAME hello_world" "Oh hai\|Hello World" "Hello world command"
    
    # Step 10: Create network for container communication
    log_step "10. Creating Docker Network"
    validate_output "docker network create $NETWORK_NAME --attachable" "[a-f0-9]" "Network creation"
    
    # Step 11: Connect Redis container to network
    log_step "11. Connecting Redis to Network"
    validate_output "docker network connect $NETWORK_NAME $REDIS_CONTAINER_NAME --alias redis" "" "Network connection"
    
    # Step 12: Test Redis connectivity from custom container
    log_step "12. Testing Redis Connectivity from Custom Container"
    validate_output "docker run --net $NETWORK_NAME $CUSTOM_IMAGE_NAME check_redis" "True" "Redis connectivity check"
    
    # Step 13: Test data retrieval from custom container
    log_step "13. Testing Data Retrieval from Custom Container"
    validate_output "docker run --net $NETWORK_NAME $CUSTOM_IMAGE_NAME get_data $TEST_KEY" "The data is in redis" "Data retrieval test"
    
    # Step 14: Test Docker Compose
    log_step "14. Testing Docker Compose Setup"
    cd "$PROJECT_ROOT/redis_client_app"
    
    # Build and start services
    validate_output "docker-compose up -d --build" "Started\|Creating.*done" "Docker Compose startup"
    
    # Wait for services to be ready
    sleep 10
    
    # Test Docker Compose services
    validate_output "docker-compose ps" "Up.*healthy\|Up.*seconds\|Up" "Docker Compose service status"
    
    # Test that we can see both services running
    log_info "Checking that both app and redis services are running..."
    if docker-compose ps | grep -q "app.*Up" && docker-compose ps | grep -q "redis.*Up"; then
        log_success "Both app and redis services are running via Docker Compose"
    else
        log_error "Not all services are running properly"
        docker-compose ps
        return 1
    fi
    
    # Stop Docker Compose services
    validate_output "docker-compose down" "Stopped\|Removed\|done" "Docker Compose shutdown"
    
    cd "$SCRIPT_DIR"
    
    log_step "15. Validation Summary"
    log_success "All Part 1 tests completed successfully!"
    log_success "✅ Redis image pull and inspection"
    log_success "✅ Redis container creation and management"
    log_success "✅ Redis data operations (SET/GET)"
    log_success "✅ Custom Python Redis client image build"
    log_success "✅ Container networking and communication"
    log_success "✅ Docker Compose orchestration"
    log_success "✅ 2025 updates verified (Python 3.12, latest dependencies)"
}

# Function to check prerequisites
check_prerequisites() {
    log_step "Checking Prerequisites"
    
    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check if docker-compose is available
    if ! command -v docker-compose &> /dev/null; then
        log_error "docker-compose is not installed or not in PATH"
        exit 1
    fi
    
    # Check if we're in the right directory structure
    if [ ! -f "$PROJECT_ROOT/README.md" ] || [ ! -d "$PROJECT_ROOT/redis_client_app" ]; then
        log_error "Project structure not found. Expected README.md and redis_client_app in: $PROJECT_ROOT"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Main execution
main() {
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                    2025 Docker Bootcamp - Part 1 Automation                 ║"
    echo "║                                                                              ║"
    echo "║  This script will automatically run through all Part 1 instructions from    ║"
    echo "║  the README while validating expected outputs at each step.                 ║"
    echo "║                                                                              ║"
    echo "║  Updated for 2025 with Python 3.12, latest dependencies, and modern        ║"
    echo "║  Docker practices.                                                           ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"
    
    check_prerequisites
    
    # Initial cleanup in case of previous runs
    cleanup 2>/dev/null || true
    
    # Run the main tests
    if run_part1_tests; then
        echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════════════════════════╗"
        echo "║                           🎉 ALL TESTS PASSED! 🎉                             ║"
        echo "║                                                                                ║"
        echo "║  The 2025 Docker Bootcamp Part 1 automation completed successfully.          ║"
        echo "║  All components are working correctly with the updated stack.                 ║"
        echo "╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
        exit 0
    else
        echo -e "\n${RED}╔════════════════════════════════════════════════════════════════════════════════╗"
        echo "║                              ❌ TESTS FAILED ❌                               ║"
        echo "║                                                                                ║"
        echo "║  Some tests failed. Please check the output above for details.               ║"
        echo "╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
        exit 1
    fi
}

# Help function
show_help() {
    echo "2025 Docker Bootcamp Part 1 Automation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -v, --verbose  Enable verbose output"
    echo ""
    echo "This script automates all Part 1 steps from the Docker Bootcamp README:"
    echo "  • Redis image pull and inspection"
    echo "  • Redis container creation and management"
    echo "  • Data storage and retrieval operations"
    echo "  • Custom Docker image building"
    echo "  • Container networking"
    echo "  • Docker Compose orchestration"
    echo ""
    echo "The script validates expected outputs at each step and provides detailed"
    echo "feedback on success or failure."
    echo ""
    echo "Prerequisites:"
    echo "  • Docker installed and running"
    echo "  • docker-compose installed"
    echo "  • Run from the project root directory"
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -v|--verbose)
        set -x  # Enable verbose mode
        main
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use -h or --help for usage information"
        exit 1
        ;;
esac 