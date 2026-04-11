#!/bin/bash
#
# Linux Server Health Check - Core Collection Script
# Output format: KEY=VALUE, one per line
#

set -euo pipefail

# Script version
VERSION="1.0.0"

# ANSI colors for output (optional, for debugging)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Helper function to print key-value pairs
print_kv() {
    local key="$1"
    local value="$2"
    echo "${key}=${value}"
}

# Main collection function
main() {
    # Module 1: System Information
    collect_system_info
    echo "---"

    # Module 2: Basic Resources
    collect_basic_resources
    echo "---"

    # Module 3: Network Status
    collect_network_status
    echo "---"

    # Module 4: Process and Services
    collect_process_services
    echo "---"

    # Module 5: Environment Information
    collect_environment_info
}

# Execute main function
main "$@"
