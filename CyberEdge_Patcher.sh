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

# Apply patch function from build.sh
function apply_patch() {
    local ret=1
    printf "\n"
    info "Testing $1\n"
    patch -p1 --dry-run < $1
    if [ $? == 0 ]; then
        printf "\n"
        if ask "The test run was completed successfully, apply the patch?" "Y"; then
            patch -p1 < $1
            ret=$?
        else
            ret=1
        fi
    else
        printf "\n"
        if ask "Warning: The test run completed with errors, apply the patch anyway?" "N"; then
            patch -p1 < $1
            ret=$?
        else
            ret=1
        fi
    fi	
    printf "\n"
    pause
    return $ret
}

# Show all patches in the current directory
function show_patches() {
    clear
    local IFS opt f i
    unset options
    printf "${LBLUE} ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n${NC}"
    printf "${LBLUE} Please choose the patch to apply\n${NC}"
    printf "${LBLUE} ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n${NC}"
    printf "\n"
    printf "${YELLOW}Current directory: $(pwd)${NC}\n"
    printf "\n"
    
    # Look for patch files in current directory and subdirectories
    while IFS= read -r -d $'\0' f; do
        options[i++]="$f"
    done < <(find . -type f \( -name "*.patch" -o -name "*.diff" \) -print0 2>/dev/null)
    
    if [ ${#options[@]} -eq 0 ]; then
        error "No patch files (.patch or .diff) found in current directory"
        info "Current directory contents:"
        ls -la
        return 1
    fi
    
    info "Found ${#options[@]} patch file(s)"
}

# Select a patch
function select_patch() {
    COLUMNS=12
    select opt in "${options[@]}" "Return"; do
        case $opt in
            "Return")
                return 1
                ;;
            *)
                apply_patch $opt 
                return 0
                ;;
        esac
    done
}

# Select kernel patch - main patch function from build.sh
function patch_kernel() {
    COLUMNS=12
    local IFS opt options f i pd
    
    # Check if patch directory exists
    if [ ! -d "$PATCH_DIR" ]; then
        error "Patch directory not found: $PATCH_DIR"
        if ask "Create patch directory?" "Y"; then
            mkdir -p "$PATCH_DIR"
            info "Created patch directory: $PATCH_DIR"
            info "Please add your patch files organized in subdirectories by kernel version"
            pause
            return 1
        else
            return 1
        fi
    fi
    
    printf "${LBLUE} ~~~~~~~~~~~~~~~~~~~~~~~~~~\n${NC}"
    printf "${LBLUE} Please choose the patch\n${NC}"
    printf "${LBLUE} directory closest matching\n${NC}"
    printf "${LBLUE} your kernel version\n${NC}"
    printf "${LBLUE} ~~~~~~~~~~~~~~~~~~~~~~~~~~\n${NC}"
    printf "\n"
    
    cd $PATCH_DIR
    
    # Check if there are any directories
    if [ ! "$(find . -maxdepth 1 -type d ! -name '.' 2>/dev/null)" ]; then
        error "No patch version directories found in $PATCH_DIR"
        info "Please create subdirectories for different kernel versions"
        info "Example structure:"
        info "  patches/"
        info "    ├── 4.14/"
        info "    ├── 4.19/" 
        info "    └── 5.4/"
        cd - > /dev/null
        pause
        return 1
    fi
    
    while IFS= read -r -d $'\0' f; do
        options[i++]="$f"
    done < <(find * -maxdepth 0 -type d -print0 2>/dev/null)
    
    select opt in "${options[@]}" "Return"; do
        case $opt in
            "Return")
                cd - > /dev/null
                return 1
                ;;
            *)
                cd $opt 
                while true; do
                    clear
                    show_patches
                    if [ $? -eq 0 ]; then
                        select_patch || break
                    else
                        break
                    fi
                done
                break
                ;;
        esac
    done

    cd - > /dev/null
    pause
    return 0
}

# Original defconfig modification function
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
    printf "\t##                                              ##\n"
    printf "\t##################################################\n"
    printf "${NC}"
    printf "\n"
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
            patch_kernel
            ;;
        "both"|"all")
            patch_kernel
            modify_defconfig
            ;;
        *)
            echo "Usage: $0 [defconfig|patch|both]"
            echo "  defconfig - Modify kernel defconfig with NetHunter configs"
            echo "  patch     - Apply kernel patches"
            echo "  both      - Apply patches then modify defconfig"
            echo "  (no args) - Show interactive menu"
            exit 1
            ;;
    esac
fi