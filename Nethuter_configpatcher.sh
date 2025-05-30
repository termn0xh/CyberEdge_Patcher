#!/bin/bash

# Configuration variables
DEFCONFIG_NAME="your_defconfig_name"  # Change this to your defconfig name (without _defconfig suffix)
CONFIGS_FILE="nethunter_configs"      # Change this to your configs file name
ARM="arm64"                          # Change to "arm" for 32-bit ARM or "arm64" for 64-bit ARM

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Validate ARM architecture
if [[ "$ARM" != "arm" && "$ARM" != "arm64" ]]; then
    print_error "ARM variable must be either 'arm' or 'arm64'. Current value: $ARM"
    exit 1
fi

# Set defconfig path
DEFCONFIG_PATH="arch/$ARM/configs/${DEFCONFIG_NAME}_defconfig"

# Check if we're in a kernel source directory
if [[ ! -d "arch" || ! -d "kernel" ]]; then
    print_error "This doesn't appear to be a kernel source directory"
    print_error "Please run this script from the kernel source root"
    exit 1
fi

# Check if defconfig exists
if [[ ! -f "$DEFCONFIG_PATH" ]]; then
    print_error "Defconfig file not found: $DEFCONFIG_PATH"
    print_error "Available defconfigs in arch/$ARM/configs/:"
    ls -1 "arch/$ARM/configs/" | grep "_defconfig$" | head -10
    exit 1
fi

# Check if configs file exists
if [[ ! -f "$CONFIGS_FILE" ]]; then
    print_error "Config file not found: $CONFIGS_FILE"
    exit 1
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
            # Config doesn't exist, skip it as requested
            print_warning "Skipping $config_name (doesn't exist in defconfig)"
            skipped_count=$((skipped_count + 1))
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
            echo "$disabled_config" >> "$DEFCONFIG_PATH"
            print_warning "Added disabled config: $config_name"
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
echo
print_status "Defconfig updated: $DEFCONFIG_PATH"
print_status "Backup created: $BACKUP_FILE"

# Optional: Sort the defconfig file
read -p "Do you want to sort the defconfig file? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sort "$DEFCONFIG_PATH" -o "$DEFCONFIG_PATH"
    print_success "Defconfig file sorted alphabetically"
fi

print_success "Script execution completed!"
