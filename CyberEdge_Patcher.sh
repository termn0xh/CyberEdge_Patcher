#!/bin/bash

# Configuration variables
DEFCONFIG_NAME="stone"  # Change this to your defconfig name (without _defconfig suffix)
CONFIGS_FILE="nethunter_configs.txt"      # Change this to your configs file name
ARM="arm64"                          # Change to "arm" for 32-bit ARM or "arm64" for 64-bit ARM
PATCH_DIR="patches"                  # Directory containing kernel patches organized by version

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
LBLUE='\033[1;34m'
LMAGENTA='\033[1;35m'
LCYAN='\033[1;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    printf "${LCYAN}[   INFO   ]${NC} $*${NC}\n"
}

success() {
    printf "${GREEN}[ SUCCESS  ]${NC} $*${NC}\n"
}

warning() {
    printf "${YELLOW}[ WARNING  ]${NC} $*${NC}\n"
}

error() {
    printf "${LMAGENTA}[  ERROR   ]${NC} $*${NC}\n"
}

question() {
    printf "${YELLOW}[ QUESTION ]${NC} "
}

# Ask function from build.sh
function ask() {
    # http://djm.me/ask
    while true; do
        if [ "${2:-}" = "Y" ]; then
            prompt="Y/n"
            default=Y
        elif [ "${2:-}" = "N" ]; then
            prompt="y/N"
            default=N
        else
            prompt="y/n"
            default=
        fi

        # Ask the question
        question	
        read -p "$1 [$prompt] " REPLY

        # Default?
        if [ -z "$REPLY" ]; then
            REPLY=$default
        fi

        # Check if the reply is valid
        case "$REPLY" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac
    done
}

# Pause function from build.sh
function pause() {
    local message="$@"
    [ -z $message ] && message="Press [Enter] to continue.."
    read -p "$message" readEnterkey
}

# Function to detect kernel version from Makefile
function detect_kernel_version() {
    if [ -f "Makefile" ]; then
        local version=$(grep "^VERSION = " Makefile | cut -d' ' -f3)
        local patchlevel=$(grep "^PATCHLEVEL = " Makefile | cut -d' ' -f3)
        local sublevel=$(grep "^SUBLEVEL = " Makefile | cut -d' ' -f3)
        if [ -n "$version" ] && [ -n "$patchlevel" ]; then
            if [ -n "$sublevel" ] && [ "$sublevel" != "0" ]; then
                echo "${version}.${patchlevel}.${sublevel}"
            else
                echo "${version}.${patchlevel}"
            fi
        fi
    fi
}

# Function to get patch description from patch file
function get_patch_description() {
    local patch_file="$1"
    local desc=""
    
    # Try to get description from patch header
    if [ -f "$patch_file" ]; then
        # Look for Subject: line first
        desc=$(grep -m 1 "^Subject:" "$patch_file" 2>/dev/null | sed 's/^Subject: *\[PATCH[^]]*\] *//' | sed 's/^Subject: *//')
        
        # If no Subject found, look for first line after ---
        if [ -z "$desc" ]; then
            desc=$(awk '/^---/{getline; if($0 !~ /^$/ && $0 !~ /^ / && $0 !~ /^diff/ && $0 !~ /^index/) {print; exit}}' "$patch_file" 2>/dev/null)
        fi
        
        # If still no description, use filename without extension
        if [ -z "$desc" ]; then
            desc=$(basename "$patch_file" | sed 's/\.[^.]*$//')
        fi
        
        # Truncate if too long
        if [ ${#desc} -gt 60 ]; then
            desc="${desc:0:57}..."
        fi
    fi
    
    echo "$desc"
}

# Function to count patches in a directory
function count_patches() {
    local dir="$1"
    if [ -d "$dir" ]; then
        find "$dir" -maxdepth 1 -type f \( -name "*.patch" -o -name "*.diff" \) | wc -l
    else
        echo "0"
    fi
}

# Enhanced function to show kernel version directories with details
function show_kernel_versions() {
    clear
    printf "${LBLUE} ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n${NC}"
    printf "${LBLUE} Available Kernel Versions & Patch Sets\n${NC}"
    printf "${LBLUE} ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n${NC}"
    printf "\n"
    
    local current_kernel=$(detect_kernel_version)
    if [ -n "$current_kernel" ]; then
        printf "${GREEN}Current kernel version detected: ${current_kernel}${NC}\n"
        printf "\n"
    fi
    
    printf "${YELLOW}%-15s %-10s %s${NC}\n" "Version" "Patches" "Description"
    printf "${YELLOW}%-15s %-10s %s${NC}\n" "-------" "-------" "-----------"
    
    # Check if patch directory exists
    if [ ! -d "$PATCH_DIR" ]; then
        error "Patch directory not found: $PATCH_DIR"
        return 1
    fi
    
    cd "$PATCH_DIR"
    
    # List all subdirectories
    local has_dirs=false
    for dir in */; do
        if [ -d "$dir" ]; then
            has_dirs=true
            local version_name=$(basename "$dir")
            local patch_count=$(count_patches "$dir")
            local desc_file="$dir/README.txt"
            local description=""
            
            # Try to get description from README file
            if [ -f "$desc_file" ]; then
                description=$(head -n 1 "$desc_file" 2>/dev/null | cut -c1-40)
            elif [ -f "$dir/description.txt" ]; then
                description=$(head -n 1 "$dir/description.txt" 2>/dev/null | cut -c1-40)
            else
                description="Kernel patches for version $version_name"
            fi
            
            # Highlight if matches current kernel
            if [ "$version_name" = "$current_kernel" ]; then
                printf "${GREEN}%-15s %-10s %s (CURRENT)${NC}\n" "$version_name" "$patch_count" "$description"
            else
                printf "%-15s %-10s %s\n" "$version_name" "$patch_count" "$description"
            fi
        fi
    done
    
    cd - > /dev/null
    
    if [ "$has_dirs" = false ]; then
        error "No kernel version directories found in $PATCH_DIR"
        return 1
    fi
    
    printf "\n"
    return 0
}

# Enhanced function to show patches in selected version directory
function show_patches_in_version() {
    local version_dir="$1"
    clear
    printf "${LBLUE} ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n${NC}"
    printf "${LBLUE} Patches available in kernel version: ${version_dir}\n${NC}"
    printf "${LBLUE} ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n${NC}"
    printf "\n"
    
    local patch_count=$(count_patches ".")
    if [ "$patch_count" -eq 0 ]; then
        error "No patch files (.patch or .diff) found in $(pwd)"
        return 1
    fi
    
    printf "${GREEN}Found ${patch_count} patch file(s)${NC}\n"
    printf "\n"
    printf "${YELLOW}%-5s %-30s %s${NC}\n" "No." "Filename" "Description"
    printf "${YELLOW}%-5s %-30s %s${NC}\n" "---" "--------" "-----------"
    
    local counter=1
    # Create array of patches with descriptions
    unset patch_files
    unset patch_descriptions
    declare -a patch_files
    declare -a patch_descriptions
    
    while IFS= read -r -d $'\0' patch_file; do
        local filename=$(basename "$patch_file")
        local description=$(get_patch_description "$patch_file")
        
        patch_files[counter]="$patch_file"
        patch_descriptions[counter]="$description"
        
        printf "%-5d %-30s %s\n" "$counter" "${filename:0:30}" "$description"
        ((counter++))
    done < <(find . -maxdepth 1 -type f \( -name "*.patch" -o -name "*.diff" \) -print0 | sort -z)
    
    printf "\n"
    return 0
}

# Enhanced patch selection with preview
function select_patch_enhanced() {
    local kernel_root="$1"
    local options=("Apply individual patches" "Apply all patches in order" "Preview patch content" "Return to version selection")
    
    printf "${LCYAN}Patch management options:${NC}\n"
    printf "\n"
    
    COLUMNS=12
    select opt in "${options[@]}"; do
        case $REPLY in
            1)
                select_individual_patch "$kernel_root"
                break
                ;;
            2)
                apply_all_patches "$kernel_root"
                break
                ;;
            3)
                preview_patch_content
                ;;
            4)
                return 1
                ;;
            *)
                error "Please select a valid option (1-4)"
                ;;
        esac
    done
}

# Function to select and apply individual patches
function select_individual_patch() {
    local kernel_root="$1"
    printf "\n${LCYAN}Select patch number to apply (or 0 to return):${NC}\n"
    read -p "Patch number: " patch_num
    
    if [ "$patch_num" = "0" ]; then
        return 1
    elif [ "$patch_num" -ge 1 ] && [ "$patch_num" -lt "${#patch_files[@]}" ]; then
        local selected_patch="${patch_files[$patch_num]}"
        if [ -n "$selected_patch" ]; then
            printf "\n${YELLOW}Selected: $(basename "$selected_patch")${NC}\n"
            printf "${YELLOW}Description: ${patch_descriptions[$patch_num]}${NC}\n"
            apply_patch "$selected_patch" "$kernel_root"
        else
            error "Invalid patch selection"
        fi
    else
        error "Invalid patch number. Please select between 1 and $((${#patch_files[@]}-1))"
    fi
}

# Function to apply all patches in directory
function apply_all_patches() {
    local kernel_root="$1"
    printf "\n${YELLOW}Applying all patches in current directory...${NC}\n"
    if ask "Are you sure you want to apply all patches?" "N"; then
        local applied=0
        local failed=0
        
        for i in $(seq 1 $((${#patch_files[@]}-1))); do
            local patch_file="${patch_files[$i]}"
            if [ -n "$patch_file" ]; then
                printf "\n${LCYAN}Applying patch $i of $((${#patch_files[@]}-1)): $(basename "$patch_file")${NC}\n"
                if apply_patch_silent "$patch_file" "$kernel_root"; then
                    ((applied++))
                    success "Applied: $(basename "$patch_file")"
                else
                    ((failed++))
                    error "Failed: $(basename "$patch_file")"
                fi
            fi
        done
        
        printf "\n${LBLUE}Batch apply results:${NC}\n"
        printf "  Applied successfully: $applied\n"
        printf "  Failed: $failed\n"
        printf "  Total: $((applied + failed))\n"
    fi
}

# Function to preview patch content
function preview_patch_content() {
    printf "\n${LCYAN}Select patch number to preview (or 0 to return):${NC}\n"
    read -p "Patch number: " patch_num
    
    if [ "$patch_num" = "0" ]; then
        return
    elif [ "$patch_num" -ge 1 ] && [ "$patch_num" -lt "${#patch_files[@]}" ]; then
        local selected_patch="${patch_files[$patch_num]}"
        if [ -n "$selected_patch" ]; then
            clear
            printf "${LBLUE}Preview of: $(basename "$selected_patch")${NC}\n"
            printf "${LBLUE}Description: ${patch_descriptions[$patch_num]}${NC}\n"
            printf "${YELLOW}${'='*60}${NC}\n"
            
            # Show first 50 lines of patch
            head -n 50 "$selected_patch"
            
            printf "\n${YELLOW}${'='*60}${NC}\n"
            local total_lines=$(wc -l < "$selected_patch")
            printf "${LCYAN}Showing first 50 lines of $total_lines total lines${NC}\n"
            pause
        fi
    else
        error "Invalid patch number"
    fi
}

# Silent patch application for batch operations
function apply_patch_silent() {
    local patch_file="$1"
    local kernel_root="$2"
    local current_dir=$(pwd)
    local ret=1
    
    # Change to kernel root directory for patching
    cd "$kernel_root"
    
    # Test patch first
    if patch -p1 --dry-run < "$current_dir/$patch_file" >/dev/null 2>&1; then
        # Apply patch
        if patch -p1 < "$current_dir/$patch_file" >/dev/null 2>&1; then
            ret=0
        fi
    fi
    
    # Return to patch directory
    cd "$current_dir"
    return $ret
}

# Apply patch function from build.sh (enhanced)
function apply_patch() {
    local patch_file="$1"
    local kernel_root="$2"
    local current_dir=$(pwd)
    local ret=1
    
    printf "\n${LBLUE}Testing patch: $(basename "$patch_file")${NC}\n"
    printf "${YELLOW}Description: $(get_patch_description "$patch_file")${NC}\n"
    printf "${BLUE}Patch location: $current_dir/$patch_file${NC}\n"
    printf "${BLUE}Applying to kernel: $kernel_root${NC}\n"
    printf "\n"
    
    # Show patch statistics
    local add_lines=$(grep "^+" "$patch_file" | wc -l)
    local del_lines=$(grep "^-" "$patch_file" | wc -l)
    local files_changed=$(grep "^diff --git" "$patch_file" | wc -l)
    
    printf "${LCYAN}Patch statistics:${NC}\n"
    printf "  Files changed: $files_changed\n"
    printf "  Lines added: $add_lines\n"
    printf "  Lines deleted: $del_lines\n"
    printf "\n"
    
    # Change to kernel root directory for patching
    cd "$kernel_root"
    
    # Test run
    info "Running dry-run test...\n"
    patch -p1 --dry-run < "$current_dir/$patch_file"
    local test_result=$?
    
    if [ $test_result == 0 ]; then
        printf "\n${GREEN}✓ Dry-run test passed successfully${NC}\n"
        if ask "Apply this patch?" "Y"; then
            patch -p1 < "$current_dir/$patch_file"
            ret=$?
            if [ $ret == 0 ]; then
                success "Patch applied successfully!"
            else
                error "Patch application failed!"
            fi
        else
            ret=1
        fi
    else
        printf "\n${RED}✗ Dry-run test failed with errors${NC}\n"
        if ask "Warning: Test failed. Apply patch anyway?" "N"; then
            patch -p1 < "$current_dir/$patch_file"
            ret=$?
            if [ $ret == 0 ]; then
                warning "Patch applied despite test failure"
            else
                error "Patch application failed!"
            fi
        else
            ret=1
        fi
    fi	
    
    # Return to patch directory
    cd "$current_dir"
    
    printf "\n"
    pause
    return $ret
}

# Enhanced kernel patch selection function
function patch_kernel() {
    COLUMNS=12
    local IFS opt options f i
    local KERNEL_ROOT=$(pwd)  # Store the kernel root directory
    
    # Check if patch directory exists
    if [ ! -d "$PATCH_DIR" ]; then
        error "Patch directory not found: $PATCH_DIR"
        if ask "Create patch directory structure?" "Y"; then
            mkdir -p "$PATCH_DIR"
            info "Created patch directory: $PATCH_DIR"
            
            # Create example structure
            local current_kernel=$(detect_kernel_version)
            if [ -n "$current_kernel" ]; then
                mkdir -p "$PATCH_DIR/$current_kernel"
                echo "Patches for kernel version $current_kernel" > "$PATCH_DIR/$current_kernel/README.txt"
                info "Created version directory: $PATCH_DIR/$current_kernel"
            fi
            
            info "Example patch directory structure:"
            info "  $PATCH_DIR/"
            info "    ├── 4.14/"
            info "    │   ├── README.txt"
            info "    │   ├── 001-security-fix.patch"
            info "    │   └── 002-driver-update.patch"
            info "    ├── 4.19/"
            info "    └── 5.4/"
            pause
            return 1
        else
            return 1
        fi
    fi
    
    while true; do
        # Always return to kernel root before showing versions
        cd "$KERNEL_ROOT"
        
        if ! show_kernel_versions; then
            pause
            return 1
        fi
        
        cd "$PATCH_DIR"
        
        # Build options array
        unset options
        local i=0
        while IFS= read -r -d 

# Original defconfig modification function (unchanged)
function modify_defconfig() {
    # Validate ARM architecture
    if [[ "$ARM" != "arm" && "$ARM" != "arm64" ]]; then
        print_error "ARM variable must be either 'arm' or 'arm64'. Current value: $ARM"
        return 1
    fi

    # Set defconfig path
    DEFCONFIG_PATH="arch/$ARM/configs/${DEFCONFIG_NAME}_defconfig"

    # Check if we're in a kernel source directory
    if [[ ! -d "arch" || ! -d "kernel" ]]; then
        print_error "This doesn't appear to be a kernel source directory"
        print_error "Please run this script from the kernel source root"
        return 1
    fi

    # Check if defconfig exists
    if [[ ! -f "$DEFCONFIG_PATH" ]]; then
        print_error "Defconfig file not found: $DEFCONFIG_PATH"
        print_error "Available defconfigs in arch/$ARM/configs/:"
        ls -1 "arch/$ARM/configs/" | grep "_defconfig$" | head -10
        return 1
    fi

    # Check if configs file exists
    if [[ ! -f "$CONFIGS_FILE" ]]; then
        print_error "Config file not found: $CONFIGS_FILE"
        return 1
    fi

    print_status "Starting kernel defconfig configuration..."
    print_status "Architecture: $ARM"
    print_status "Defconfig: $DEFCONFIG_PATH"
    print_status "Config source: $CONFIGS_FILE"
    echo

    # Create backup of original defconfig
    BACKUP_FILE="${DEFCONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$DEFCONFIG_PATH" "$BACKUP_FILE"
    print_status "Created backup: $BACKUP_FILE"

    # Counters for statistics
    updated_count=0
    added_count=0
    already_correct_count=0
    skipped_count=0
    total_configs=0

    # Process the configs file
    while IFS= read -r line; do
        # Skip empty lines
        if [[ -z "$line" ]]; then
            continue
        fi
        
        # Skip regular comments but NOT "# CONFIG_X is not set" lines
        if [[ "$line" =~ ^[[:space:]]*# ]] && [[ ! "$line" =~ CONFIG_.*is[[:space:]]+not[[:space:]]+set ]]; then
            continue
        fi
        
        # Check for configs missing CONFIG_ prefix and fix them
        if [[ "$line" =~ ^([A-Z0-9_]+)=(.+)$ ]] && [[ ! "$line" =~ ^CONFIG_ ]]; then
            config_base="${BASH_REMATCH[1]}"
            config_value="${BASH_REMATCH[2]}"
            line="CONFIG_$config_base=$config_value"
            print_warning "Fixed missing CONFIG_ prefix: $config_base -> CONFIG_$config_base"
        fi
        
        # Handle both "# CONFIG_X is not set" and "CONFIG_X is not set" formats
        if [[ "$line" =~ ^#?[[:space:]]*CONFIG_([^[:space:]]+)[[:space:]]+is[[:space:]]+not[[:space:]]+set ]]; then
            config_name="CONFIG_${BASH_REMATCH[1]}"
            disabled_config="# $config_name is not set"
            
            total_configs=$((total_configs + 1))
            
            # Check current state in defconfig
            if grep -q "^# $config_name is not set" "$DEFCONFIG_PATH"; then
                print_success "$config_name already disabled"
                already_correct_count=$((already_correct_count + 1))
            elif grep -q "^$config_name=" "$DEFCONFIG_PATH"; then
                # Config is enabled, disable it
                sed -i "s/^$config_name=.*$/$disabled_config/" "$DEFCONFIG_PATH"
                print_warning "Disabled $config_name (was enabled)"
                updated_count=$((updated_count + 1))
            else
                # Config doesn't exist, add the disabled config
                echo "$disabled_config" >> "$DEFCONFIG_PATH"
                print_warning "Added disabled config: $disabled_config"
                added_count=$((added_count + 1))
            fi
        # Extract config name and value for enabled configs
        elif [[ "$line" =~ ^CONFIG_([^=]+)=(.+)$ ]]; then
            config_name="CONFIG_${BASH_REMATCH[1]}"
            config_value="${BASH_REMATCH[2]}"
            full_config="$config_name=$config_value"
            
            total_configs=$((total_configs + 1))
            
            # Check if config exists in defconfig
            if grep -q "^$config_name=" "$DEFCONFIG_PATH"; then
                # Config exists, check if it has the correct value
                current_value=$(grep "^$config_name=" "$DEFCONFIG_PATH" | cut -d'=' -f2)
                if [[ "$current_value" == "$config_value" ]]; then
                    print_success "$config_name already set correctly to $config_value"
                    already_correct_count=$((already_correct_count + 1))
                else
                    # Update existing config
                    sed -i "s/^$config_name=.*$/$full_config/" "$DEFCONFIG_PATH"
                    print_warning "Updated $config_name from $current_value to $config_value"
                    updated_count=$((updated_count + 1))
                fi
            elif grep -q "^# $config_name is not set" "$DEFCONFIG_PATH"; then
                # Config is explicitly disabled, enable it
                sed -i "s/^# $config_name is not set$/$full_config/" "$DEFCONFIG_PATH"
                print_warning "Enabled $config_name (was disabled) and set to $config_value"
                updated_count=$((updated_count + 1))
            else
                # Config doesn't exist anywhere, add it
                echo "$full_config" >> "$DEFCONFIG_PATH"
                print_warning "Added new config: $full_config"
                added_count=$((added_count + 1))
            fi
        elif [[ "$line" =~ ^CONFIG_([^=]+)$ ]]; then
            # Handle configs without values (like CONFIG_MODULES)
            config_name="$line"
            full_config="$config_name=y"
            
            total_configs=$((total_configs + 1))
            
            if grep -q "^$config_name=" "$DEFCONFIG_PATH"; then
                current_value=$(grep "^$config_name=" "$DEFCONFIG_PATH" | cut -d'=' -f2)
                if [[ "$current_value" == "y" ]]; then
                    print_success "$config_name already enabled"
                    already_correct_count=$((already_correct_count + 1))
                else
                    sed -i "s/^$config_name=.*$/$full_config/" "$DEFCONFIG_PATH"
                    print_warning "Updated $config_name from $current_value to y"
                    updated_count=$((updated_count + 1))
                fi
            elif grep -q "^# $config_name is not set" "$DEFCONFIG_PATH"; then
                sed -i "s/^# $config_name is not set$/$full_config/" "$DEFCONFIG_PATH"
                print_warning "Enabled $config_name (was disabled)"
                updated_count=$((updated_count + 1))
            else
                # Config doesn't exist anywhere, add it
                echo "$full_config" >> "$DEFCONFIG_PATH"
                print_warning "Added new config: $full_config"
                added_count=$((added_count + 1))
            fi
        else
            # Skip invalid lines but show warning for non-comment lines
            if [[ ! "$line" =~ ^[[:space:]]*# ]]; then
                print_warning "Skipping invalid config line: $line"
            fi
        fi
    done < "$CONFIGS_FILE"

    echo
    print_status "Configuration completed!"
    echo "Statistics:"
    echo "  Total configs processed: $total_configs"
    echo "  Already correct: $already_correct_count"
    echo "  Updated: $updated_count"
    echo "  Added new: $added_count"
    if [ $skipped_count -gt 0 ]; then
        echo "  Skipped (non-existent): $skipped_count"
    fi
    echo
    print_status "Defconfig updated: $DEFCONFIG_PATH"
    print_status "Backup created: $BACKUP_FILE"

    # Optional: Sort the defconfig file
    if ask "Do you want to sort the defconfig file?" "N"; then
        sort "$DEFCONFIG_PATH" -o "$DEFCONFIG_PATH"
        print_success "Defconfig file sorted alphabetically"
    fi

    print_success "Defconfig modification completed!"
    pause
}

# Main menu function
show_main_menu() {
    clear
    printf "${LBLUE}"
    printf "\t##################################################\n"
    printf "\t##                                              ##\n"
    printf "\t##      CyberEdge Config & Kernel Patcher       ##\n"
    printf "\t##               Enhanced Edition               ##\n"
    printf "\t##################################################\n"
    printf "${NC}"
    printf "\n"
    
    local current_kernel=$(detect_kernel_version)
    if [ -n "$current_kernel" ]; then
        printf "${GREEN}Detected kernel version: ${current_kernel}${NC}\n"
    fi
    printf "${YELLOW}Please select an operation:${NC}\n"
    printf "\n"
}

# Operation selection menu
show_operation_menu() {
    local operations=("Modify kernel defconfig with NetHunter configs" "Apply kernel patches" "Both: Apply patches then modify defconfig" "Exit")
    
    show_main_menu
    
    printf "${LCYAN}Available operations:${NC}\n"
    printf "\n"
    
    COLUMNS=12
    select operation in "${operations[@]}"; do
        case $REPLY in
            1)
                clear
                info "Selected: Modify kernel defconfig"
                modify_defconfig
                break
                ;;
            2)
                clear
                info "Selected: Apply kernel patches"
                patch_kernel
                break
                ;;
            3)
                clear
                info "Selected: Both operations"
                printf "\n"
                info "Step 1: Applying kernel patches"
                patch_kernel
                printf "\n"
                info "Step 2: Modifying defconfig"
                modify_defconfig
                break
                ;;
            4)
                printf "${NC}\n\n"
                success "Goodbye!"
                exit 0
                ;;
            *)
                error "Please select a valid option (1-4)"
                printf "\n"
                ;;
        esac
    done
}

# Check if we're in a kernel source directory for patching
function check_kernel_source() {
    if [[ ! -d "arch" || ! -d "kernel" ]]; then
        print_error "This doesn't appear to be a kernel source directory"
        print_error "Please run this script from the kernel source root"
        exit 1
    fi
}

# Main execution
check_kernel_source

# If no arguments provided, show interactive menu
if [ $# -eq 0 ]; then
    while true; do
        show_operation_menu
        printf "\n"
        if ask "Do you want to perform another operation?" "N"; then
            continue
        else
            printf "${NC}\n"
            success "All operations completed. Goodbye!"
            break
        fi
    done
else
    # Handle command line arguments for automation (backward compatibility)
    case "$1" in
        "defconfig"|"config")
            modify_defconfig
            ;;
        "patch"|"patches")
            patch\0' f; do
            options[i++]="$f"
        done < <(find * -maxdepth 0 -type d -print0 2>/dev/null | sort -z)
        
        if [ ${#options[@]} -eq 0 ]; then
            error "No kernel version directories found"
            cd "$KERNEL_ROOT"
            pause
            return 1
        fi
        
        printf "${LCYAN}Select kernel version to patch:${NC}\n"
        printf "\n"
        
        select opt in "${options[@]}" "Return to main menu"; do
            case $opt in
                "Return to main menu")
                    cd "$KERNEL_ROOT"
                    return 1
                    ;;
                *)
                    if [ -n "$opt" ]; then
                        cd "$opt"
                        printf "\n${GREEN}Selected kernel version: $opt${NC}\n"
                        printf "${BLUE}Patch directory: $(pwd)${NC}\n"
                        printf "${BLUE}Kernel root: $KERNEL_ROOT${NC}\n"
                        
                        while true; do
                            if show_patches_in_version "$opt"; then
                                # Pass kernel root to patch functions
                                select_patch_enhanced "$KERNEL_ROOT"
                                if [ $? -eq 1 ]; then
                                    break
                                fi
                            else
                                break
                            fi
                        done
                        
                        cd ..
                        break
                    else
                        error "Invalid selection"
                    fi
                    ;;
            esac
        done
        
        cd "$KERNEL_ROOT"
        
        if ! ask "Return to kernel version selection?" "N"; then
            break
        fi
    done
    
    return 0
}

# Original defconfig modification function (unchanged)
function modify_defconfig() {
    # Validate ARM architecture
    if [[ "$ARM" != "arm" && "$ARM" != "arm64" ]]; then
        print_error "ARM variable must be either 'arm' or 'arm64'. Current value: $ARM"
        return 1
    fi

    # Set defconfig path
    DEFCONFIG_PATH="arch/$ARM/configs/${DEFCONFIG_NAME}_defconfig"

    # Check if we're in a kernel source directory
    if [[ ! -d "arch" || ! -d "kernel" ]]; then
        print_error "This doesn't appear to be a kernel source directory"
        print_error "Please run this script from the kernel source root"
        return 1
    fi

    # Check if defconfig exists
    if [[ ! -f "$DEFCONFIG_PATH" ]]; then
        print_error "Defconfig file not found: $DEFCONFIG_PATH"
        print_error "Available defconfigs in arch/$ARM/configs/:"
        ls -1 "arch/$ARM/configs/" | grep "_defconfig$" | head -10
        return 1
    fi

    # Check if configs file exists
    if [[ ! -f "$CONFIGS_FILE" ]]; then
        print_error "Config file not found: $CONFIGS_FILE"
        return 1
    fi

    print_status "Starting kernel defconfig configuration..."
    print_status "Architecture: $ARM"
    print_status "Defconfig: $DEFCONFIG_PATH"
    print_status "Config source: $CONFIGS_FILE"
    echo

    # Create backup of original defconfig
    BACKUP_FILE="${DEFCONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$DEFCONFIG_PATH" "$BACKUP_FILE"
    print_status "Created backup: $BACKUP_FILE"

    # Counters for statistics
    updated_count=0
    added_count=0
    already_correct_count=0
    skipped_count=0
    total_configs=0

    # Process the configs file
    while IFS= read -r line; do
        # Skip empty lines
        if [[ -z "$line" ]]; then
            continue
        fi
        
        # Skip regular comments but NOT "# CONFIG_X is not set" lines
        if [[ "$line" =~ ^[[:space:]]*# ]] && [[ ! "$line" =~ CONFIG_.*is[[:space:]]+not[[:space:]]+set ]]; then
            continue
        fi
        
        # Check for configs missing CONFIG_ prefix and fix them
        if [[ "$line" =~ ^([A-Z0-9_]+)=(.+)$ ]] && [[ ! "$line" =~ ^CONFIG_ ]]; then
            config_base="${BASH_REMATCH[1]}"
            config_value="${BASH_REMATCH[2]}"
            line="CONFIG_$config_base=$config_value"
            print_warning "Fixed missing CONFIG_ prefix: $config_base -> CONFIG_$config_base"
        fi
        
        # Handle both "# CONFIG_X is not set" and "CONFIG_X is not set" formats
        if [[ "$line" =~ ^#?[[:space:]]*CONFIG_([^[:space:]]+)[[:space:]]+is[[:space:]]+not[[:space:]]+set ]]; then
            config_name="CONFIG_${BASH_REMATCH[1]}"
            disabled_config="# $config_name is not set"
            
            total_configs=$((total_configs + 1))
            
            # Check current state in defconfig
            if grep -q "^# $config_name is not set" "$DEFCONFIG_PATH"; then
                print_success "$config_name already disabled"
                already_correct_count=$((already_correct_count + 1))
            elif grep -q "^$config_name=" "$DEFCONFIG_PATH"; then
                # Config is enabled, disable it
                sed -i "s/^$config_name=.*$/$disabled_config/" "$DEFCONFIG_PATH"
                print_warning "Disabled $config_name (was enabled)"
                updated_count=$((updated_count + 1))
            else
                # Config doesn't exist, add the disabled config
                echo "$disabled_config" >> "$DEFCONFIG_PATH"
                print_warning "Added disabled config: $disabled_config"
                added_count=$((added_count + 1))
            fi
        # Extract config name and value for enabled configs
        elif [[ "$line" =~ ^CONFIG_([^=]+)=(.+)$ ]]; then
            config_name="CONFIG_${BASH_REMATCH[1]}"
            config_value="${BASH_REMATCH[2]}"
            full_config="$config_name=$config_value"
            
            total_configs=$((total_configs + 1))
            
            # Check if config exists in defconfig
            if grep -q "^$config_name=" "$DEFCONFIG_PATH"; then
                # Config exists, check if it has the correct value
                current_value=$(grep "^$config_name=" "$DEFCONFIG_PATH" | cut -d'=' -f2)
                if [[ "$current_value" == "$config_value" ]]; then
                    print_success "$config_name already set correctly to $config_value"
                    already_correct_count=$((already_correct_count + 1))
                else
                    # Update existing config
                    sed -i "s/^$config_name=.*$/$full_config/" "$DEFCONFIG_PATH"
                    print_warning "Updated $config_name from $current_value to $config_value"
                    updated_count=$((updated_count + 1))
                fi
            elif grep -q "^# $config_name is not set" "$DEFCONFIG_PATH"; then
                # Config is explicitly disabled, enable it
                sed -i "s/^# $config_name is not set$/$full_config/" "$DEFCONFIG_PATH"
                print_warning "Enabled $config_name (was disabled) and set to $config_value"
                updated_count=$((updated_count + 1))
            else
                # Config doesn't exist anywhere, add it
                echo "$full_config" >> "$DEFCONFIG_PATH"
                print_warning "Added new config: $full_config"
                added_count=$((added_count + 1))
            fi
        elif [[ "$line" =~ ^CONFIG_([^=]+)$ ]]; then
            # Handle configs without values (like CONFIG_MODULES)
            config_name="$line"
            full_config="$config_name=y"
            
            total_configs=$((total_configs + 1))
            
            if grep -q "^$config_name=" "$DEFCONFIG_PATH"; then
                current_value=$(grep "^$config_name=" "$DEFCONFIG_PATH" | cut -d'=' -f2)
                if [[ "$current_value" == "y" ]]; then
                    print_success "$config_name already enabled"
                    already_correct_count=$((already_correct_count + 1))
                else
                    sed -i "s/^$config_name=.*$/$full_config/" "$DEFCONFIG_PATH"
                    print_warning "Updated $config_name from $current_value to y"
                    updated_count=$((updated_count + 1))
                fi
            elif grep -q "^# $config_name is not set" "$DEFCONFIG_PATH"; then
                sed -i "s/^# $config_name is not set$/$full_config/" "$DEFCONFIG_PATH"
                print_warning "Enabled $config_name (was disabled)"
                updated_count=$((updated_count + 1))
            else
                # Config doesn't exist anywhere, add it
                echo "$full_config" >> "$DEFCONFIG_PATH"
                print_warning "Added new config: $full_config"
                added_count=$((added_count + 1))
            fi
        else
            # Skip invalid lines but show warning for non-comment lines
            if [[ ! "$line" =~ ^[[:space:]]*# ]]; then
                print_warning "Skipping invalid config line: $line"
            fi
        fi
    done < "$CONFIGS_FILE"

    echo
    print_status "Configuration completed!"
    echo "Statistics:"
    echo "  Total configs processed: $total_configs"
    echo "  Already correct: $already_correct_count"
    echo "  Updated: $updated_count"
    echo "  Added new: $added_count"
    if [ $skipped_count -gt 0 ]; then
        echo "  Skipped (non-existent): $skipped_count"
    fi
    echo
    print_status "Defconfig updated: $DEFCONFIG_PATH"
    print_status "Backup created: $BACKUP_FILE"

    # Optional: Sort the defconfig file
    if ask "Do you want to sort the defconfig file?" "N"; then
        sort "$DEFCONFIG_PATH" -o "$DEFCONFIG_PATH"
        print_success "Defconfig file sorted alphabetically"
    fi

    print_success "Defconfig modification completed!"
    pause
#}

# Main menu function
show_main_menu() {
    clear
    printf "${LBLUE}"
    printf "\t##################################################\n"
    printf "\t##                                              ##\n"
    printf "\t##      CyberEdge Config & Kernel Patcher       ##\n"
    printf "\t##               Enhanced Edition               ##\n"
    printf "\t##################################################\n"
    printf "${NC}"
    printf "\n"
    
    local current_kernel=$(detect_kernel_version)
    if [ -n "$current_kernel" ]; then
        printf "${GREEN}Detected kernel version: ${current_kernel}${NC}\n"
    fi
    printf "${YELLOW}Please select an operation:${NC}\n"
    printf "\n"
}

# Operation selection menu
show_operation_menu() {
    local operations=("Modify kernel defconfig with NetHunter configs" "Apply kernel patches" "Both: Apply patches then modify defconfig" "Exit")
    
    show_main_menu
    
    printf "${LCYAN}Available operations:${NC}\n"
    printf "\n"
    
    COLUMNS=12
    select operation in "${operations[@]}"; do
        case $REPLY in
            1)
                clear
                info "Selected: Modify kernel defconfig"
                modify_defconfig
                break
                ;;
            2)
                clear
                info "Selected: Apply kernel patches"
                patch_kernel
                break
                ;;
            3)
                clear
                info "Selected: Both operations"
                printf "\n"
                info "Step 1: Applying kernel patches"
                patch_kernel
                printf "\n"
                info "Step 2: Modifying defconfig"
                modify_defconfig
                break
                ;;
            4)
                printf "${NC}\n\n"
                success "Goodbye!"
                exit 0
                ;;
            *)
                error "Please select a valid option (1-4)"
                printf "\n"
                ;;
        esac
    done
}

# Check if we're in a kernel source directory for patching
function check_kernel_source() {
    if [[ ! -d "arch" || ! -d "kernel" ]]; then
        print_error "This doesn't appear to be a kernel source directory"
        print_error "Please run this script from the kernel source root"
        exit 1
    fi
}

# Main execution
check_kernel_source

# If no arguments provided, show interactive menu
if [ $# -eq 0 ]; then
    while true; do
        show_operation_menu
        printf "\n"
        if ask "Do you want to perform another operation?" "N"; then
            continue
        else
            printf "${NC}\n"
            success "All operations completed. Goodbye!"
            break
        fi
    done
else
    # Handle command line arguments for automation (backward compatibility)
    case "$1" in
        "defconfig"|"config")
            modify_defconfig
            ;;
        "patch"|"patches")
            patch
