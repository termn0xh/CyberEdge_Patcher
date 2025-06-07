#!/bin/bash

# ==============================================
# CyberEdge Kernel Patcher & Config Modifier
# NOT WORKING VERSION
# ==============================================
#

#=====================
#    CONFIGURATION
#=====================
DEFCONFIG_NAME="stone"     
CONFIGS_FILE="nethunter_configs.txt"
ARM="arm64"    
PATCH_DIR="patches"    
LOG_FILE="patcher.log"        
MAX_PATCH_PREVIEW_LINES=50     

#=====================
#  COLOR DEFINITIONS
#=====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
LBLUE='\033[1;34m'
LMAGENTA='\033[1;35m'
LCYAN='\033[1;36m'
NC='\033[0m' # No Color

#======================
#    INITIALIZATION
#======================
exec > >(tee -a "$LOG_FILE") 2>&1
echo -e "\n=== $(date) - Script started ==="

#=====================
#      FUNCTIONS
#=====================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; echo "[INFO] $1" >> "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; echo "[SUCCESS] $1" >> "$LOG_FILE"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; echo "[WARNING] $1" >> "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; echo "[ERROR] $1" >> "$LOG_FILE"; }

ask() {
    while true; do
        if [ "${2:-}" = "Y" ]; then prompt="Y/n"; default=Y;
        elif [ "${2:-}" = "N" ]; then prompt="y/N"; default=N;
        else prompt="y/n"; default=; fi

        echo -ne "${YELLOW}[QUESTION]${NC} $1 [$prompt] "
        read REPLY
        [ -z "$REPLY" ] && REPLY=$default
        case "$REPLY" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac
    done
}

pause() {
    echo -ne "${1:-Press [Enter] to continue...}"
    read -r
}

detect_kernel_version() {
    if [ -f "Makefile" ]; then
        local version=$(grep "^VERSION = " Makefile | cut -d' ' -f3)
        local patchlevel=$(grep "^PATCHLEVEL = " Makefile | cut -d' ' -f3)
        local sublevel=$(grep "^SUBLEVEL = " Makefile | cut -d' ' -f3)
        
        [ -n "$version" ] && [ -n "$patchlevel" ] && {
            [ -n "$sublevel" ] && [ "$sublevel" != "0" ] \
                && echo "${version}.${patchlevel}.${sublevel}" \
                || echo "${version}.${patchlevel}"
        }
    fi
}

count_patches() {
    [ -d "$1" ] && find "$1" -maxdepth 1 -type f \( -name "*.patch" -o -name "*.diff" \) | wc -l || echo "0"
}

get_patch_description() {
    local patch_file="$1" desc=""
    [ -f "$patch_file" ] && {
        desc=$(grep -m 1 "^Subject:" "$patch_file" 2>/dev/null | sed 's/^Subject: *\[PATCH[^]]*\] *//;s/^Subject: *//')
        [ -z "$desc" ] && desc=$(awk '/^---/{getline; if($0 !~ /^$/ && $0 !~ /^ / && $0 !~ /^diff/ && $0 !~ /^index/) {print; exit}}' "$patch_file" 2>/dev/null)
        [ -z "$desc" ] && desc=$(basename "$patch_file" | sed 's/\.[^.]*$//')
        [ ${#desc} -gt 60 ] && desc="${desc:0:57}..."
    }
    echo "$desc"
}

show_kernel_versions() {
    clear
    echo -e "${LBLUE}=========================================${NC}"
    echo -e "${LBLUE} Available Kernel Versions & Patch Sets ${NC}"
    echo -e "${LBLUE}=========================================${NC}\n"
    
    local current_kernel=$(detect_kernel_version)
    [ -n "$current_kernel" ] && echo -e "${GREEN}Current kernel version: ${current_kernel}${NC}\n"
    
    printf "${YELLOW}%-15s %-10s %s${NC}\n" "Version" "Patches" "Description"
    printf "${YELLOW}%-15s %-10s %s${NC}\n" "-------" "-------" "-----------"
    
    if [ ! -d "$PATCH_DIR" ]; then
        log_error "Patch directory not found: $PATCH_DIR"
        echo -e "\n${YELLOW}To fix this:${NC}"
        echo "1. mkdir -p $PATCH_DIR"
        echo "2. Create subdirs for each version (e.g., $PATCH_DIR/4.19/)"
        echo "3. Place .patch files in the appropriate directories"
        return 1
    fi

    local has_dirs=false
    while IFS= read -r -d $'\0' dir; do
        has_dirs=true
        local version_name=$(basename "$dir")
        local patch_count=$(count_patches "$dir")
        local description=""
        
        [ -f "$dir/README.txt" ] && description=$(head -n 1 "$dir/README.txt" 2>/dev/null | cut -c1-40)
        [ -z "$description" ] && description="Patches for $version_name"
        
        [ "$version_name" = "$current_kernel" ] \
            && printf "${GREEN}%-15s %-10s %s (CURRENT)${NC}\n" "$version_name" "$patch_count" "$description" \
            || printf "%-15s %-10s %s\n" "$version_name" "$patch_count" "$description"
    done < <(find "$PATCH_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    
    [ "$has_dirs" = false ] && {
        log_error "No kernel version directories found in $PATCH_DIR"
        return 1
    }
    
    echo
    return 0
}

preview_patch() {
    local patch_file="$1"
    echo -e "\n${LMAGENTA}=== Patch Preview: $(basename "$patch_file") ===${NC}"
    echo -e "${YELLOW}Description: $(get_patch_description "$patch_file")${NC}"
    
    local add_lines=$(grep -c "^+" "$patch_file")
    local del_lines=$(grep -c "^-" "$patch_file")
    local files_changed=$(grep -c "^diff --git" "$patch_file")
    
    echo -e "${LCYAN}Patch statistics:${NC}"
    echo "  Files changed: $files_changed"
    echo "  Lines added: $add_lines"
    echo "  Lines deleted: $del_lines"
    echo -e "\n${BLUE}=== Patch Content (first $MAX_PATCH_PREVIEW_LINES lines) ===${NC}"
    head -n $MAX_PATCH_PREVIEW_LINES "$patch_file" | sed 's/^/  /'
    echo -e "${BLUE}=== End Preview ===${NC}\n"
}

# Enhanced patch application function from build.sh
apply_patch() {
    local patch_file="$1" kernel_root="$2" current_dir=$(pwd)
    local ret=1
    
    cd "$kernel_root" || return 1
    
    echo -e "\n${BLUE}Testing patch: $(basename "$patch_file")${NC}"
    patch -p1 --dry-run < "$current_dir/$patch_file"
    
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}✓ Dry-run successful${NC}"
        if ask "Apply this patch?" "Y"; then
            patch -p1 < "$current_dir/$patch_file"
            ret=$?
            [ $ret -eq 0 ] && log_success "Patch applied successfully" || log_error "Patch application failed"
        else
            ret=1
        fi
    else
        echo -e "\n${RED}✗ Dry-run failed${NC}"
        if ask "Apply patch anyway?" "N"; then
            patch -p1 < "$current_dir/$patch_file"
            ret=$?
            [ $ret -eq 0 ] && log_warning "Patch applied despite dry-run failure" || log_error "Patch application failed"
        else
            ret=1
        fi
    fi
    
    cd "$current_dir"
    pause
    return $ret
}

# Enhanced patch management from build.sh
manage_patches() {
    local kernel_root="$1" current_dir=$(pwd)
    
    while true; do
        clear
        echo -e "${LBLUE}=================================${NC}"
        echo -e "${LBLUE} Managing Patches for $(basename "$current_dir") ${NC}"
        echo -e "${LBLUE}=================================${NC}\n"
        
        local patch_files=() patch_descriptions=()
        while IFS= read -r -d $'\0' file; do
            patch_files+=("$file")
            patch_descriptions+=("$(get_patch_description "$file")")
        done < <(find . -maxdepth 1 -type f \( -name "*.patch" -o -name "*.diff" \) -print0 | sort -z)
        
        if [ ${#patch_files[@]} -eq 0 ]; then
            log_error "No patch files found in $(pwd)"
            pause
            return 1
        fi
        
        for i in "${!patch_files[@]}"; do
            printf "${YELLOW}%2d)${NC} %-40s ${BLUE}%s${NC}\n" \
                "$((i+1))" "$(basename "${patch_files[$i]}")" "${patch_descriptions[$i]}"
        done
        
        echo -e "\n${YELLOW}  a) Apply all patches${NC}"
        echo -e "${YELLOW}  p) Preview a patch${NC}"
        echo -e "${YELLOW}  r) Return to version selection${NC}"
        echo -e "${YELLOW}  q) Quit to main menu${NC}"
        
        echo -ne "\n${LCYAN}Select an option:${NC} "
        read -r choice
        
        case "$choice" in
            [1-9]|[1-9][0-9])
                local selected=$((choice-1))
                [ "$selected" -lt "${#patch_files[@]}" ] && \
                    apply_patch "${patch_files[$selected]}" "$kernel_root" || {
                    log_error "Invalid selection"
                    pause
                }
                ;;
            a|A)
                echo -e "\n${GREEN}Applying all patches...${NC}"
                for patch in "${patch_files[@]}"; do
                    apply_patch "$patch" "$kernel_root"
                done
                ;;
            p|P)
                echo -ne "${LCYAN}Enter patch number to preview:${NC} "
                read -r preview_num
                if [[ "$preview_num" =~ ^[0-9]+$ ]] && [ "$preview_num" -le "${#patch_files[@]}" ] && [ "$preview_num" -gt 0 ]; then
                    preview_patch "${patch_files[$((preview_num-1))]}"
                    pause
                else
                    log_error "Invalid selection"
                    pause
                fi
                ;;
            r|R) return 0 ;;
            q|Q) return 1 ;;
            *) log_error "Invalid option"; pause ;;
        esac
    done
}

# Enhanced patch selection from build.sh
patch_kernel() {
    local KERNEL_ROOT=$(pwd)
    local LAST_PATCH_DIR="$PATCH_DIR"
    
    while true; do
        if ! show_kernel_versions; then
            pause
            return 1
        fi
        
        cd "$LAST_PATCH_DIR" || {
            log_error "Cannot access patch directory: $LAST_PATCH_DIR"
            pause
            return 1
        }
        
        local options=()
        while IFS= read -r -d $'\0' dir; do
            options+=("$(basename "$dir")")
        done < <(find * -maxdepth 0 -type d -print0 2>/dev/null | sort -z)
        
        if [ ${#options[@]} -eq 0 ]; then
            log_error "No version directories found in $LAST_PATCH_DIR"
            cd "$KERNEL_ROOT"
            pause
            return 1
        fi
        
        options+=("Return to main menu")
        
        echo -e "\n${LCYAN}Select kernel version:${NC}"
        select opt in "${options[@]}"; do
            case $opt in
                "Return to main menu")
                    cd "$KERNEL_ROOT"
                    return 1 ;;
                *)
                    if [ -n "$opt" ]; then
                        cd "$opt" || {
                            log_error "Cannot access version directory: $opt"
                            continue
                        }
                        if ! manage_patches "$KERNEL_ROOT"; then
                            cd "$KERNEL_ROOT"
                            return 1
                        fi
                        cd "$LAST_PATCH_DIR"
                        break
                    else
                        log_error "Invalid selection"
                    fi ;;
            esac
        done
        
        if ! ask "Select another version?" "N"; then
            cd "$KERNEL_ROOT"
            break
        fi
    done
}

modify_defconfig() {
    [[ "$ARM" != "arm" && "$ARM" != "arm64" ]] && {
        log_error "Invalid ARM value: $ARM (must be 'arm' or 'arm64')"
        return 1
    }

    local DEFCONFIG_PATH="arch/$ARM/configs/${DEFCONFIG_NAME}_defconfig"
    
    [[ ! -d "arch" || ! -d "kernel" ]] && {
        log_error "Not in kernel source directory"
        return 1
    }
    
    [[ ! -f "$DEFCONFIG_PATH" ]] && {
        log_error "Defconfig not found: $DEFCONFIG_PATH"
        echo "Available defconfigs:"
        ls -1 "arch/$ARM/configs/" | grep "_defconfig$" | head -10
        return 1
    }
    
    [[ ! -f "$CONFIGS_FILE" ]] && {
        log_error "Config file not found: $CONFIGS_FILE"
        return 1
    }

    log_info "Starting defconfig modification..."
    log_info "Target: $DEFCONFIG_PATH"
    log_info "Source: $CONFIGS_FILE"
    
    local BACKUP_FILE="${DEFCONFIG_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$DEFCONFIG_PATH" "$BACKUP_FILE" || {
        log_error "Failed to create backup"
        return 1
    }
    log_info "Backup created: $BACKUP_FILE"
    
    local updated=0 added=0 correct=0 skipped=0 total=0
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        # Skip comments except disabled configs
        [[ "$line" =~ ^[[:space:]]*# ]] && [[ ! "$line" =~ CONFIG_.*is[[:space:]]+not[[:space:]]+set ]] && continue
        
        # Fix missing CONFIG_ prefix
        [[ "$line" =~ ^([A-Z0-9_]+)=(.+)$ ]] && [[ ! "$line" =~ ^CONFIG_ ]] && {
            line="CONFIG_${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
            log_warning "Fixed missing CONFIG_ prefix: ${BASH_REMATCH[1]}"
        }
        
        ((total++))
        
        # Handle disabled configs
        if [[ "$line" =~ ^#?[[:space:]]*CONFIG_([^[:space:]]+)[[:space:]]+is[[:space:]]+not[[:space:]]+set ]]; then
            local config="CONFIG_${BASH_REMATCH[1]}"
            local disabled="# $config is not set"
            
            if grep -q "^# $config is not set" "$DEFCONFIG_PATH"; then
                ((correct++))
            elif grep -q "^$config=" "$DEFCONFIG_PATH"; then
                sed -i "s/^$config=.*$/$disabled/" "$DEFCONFIG_PATH" && ((updated++)) && \
                    log_warning "Disabled $config" || log_error "Failed to disable $config"
            else
                echo "$disabled" >> "$DEFCONFIG_PATH" && ((added++)) && \
                    log_warning "Added disabled $config" || log_error "Failed to add disabled $config"
            fi
        
        # Handle enabled configs
        elif [[ "$line" =~ ^(CONFIG_[^=]+)=(.*)$ ]]; then
            local config="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
            local full_line="$config=$value"
            
            if grep -q "^$config=" "$DEFCONFIG_PATH"; then
                local current=$(grep "^$config=" "$DEFCONFIG_PATH" | cut -d'=' -f2)
                if [[ "$current" == "$value" ]]; then
                    ((correct++))
                else
                    sed -i "s/^$config=.*$/$full_line/" "$DEFCONFIG_PATH" && ((updated++)) && \
                        log_warning "Updated $config from $current to $value" || \
                        log_error "Failed to update $config"
                fi
            elif grep -q "^# $config is not set" "$DEFCONFIG_PATH"; then
                sed -i "s/^# $config is not set$/$full_line/" "$DEFCONFIG_PATH" && ((updated++)) && \
                    log_warning "Enabled $config (was disabled)" || \
                    log_error "Failed to enable $config"
            else
                echo "$full_line" >> "$DEFCONFIG_PATH" && ((added++)) && \
                    log_warning "Added new config $config=$value" || \
                    log_error "Failed to add $config"
            fi
        else
            ((skipped++))
            [[ ! "$line" =~ ^[[:space:]]*# ]] && log_warning "Skipping invalid line: $line"
        fi
    done < "$CONFIGS_FILE"
    
    echo -e "\n${GREEN}Defconfig modification complete!${NC}"
    echo "Statistics:"
    echo "  Total configs processed: $total"
    echo "  Already correct: $correct"
    echo "  Updated: $updated"
    echo "  Added: $added"
    [[ $skipped -gt 0 ]] && echo "  Skipped: $skipped"
    
    ask "Sort the defconfig file?" "N" && {
        sort -o "$DEFCONFIG_PATH" "$DEFCONFIG_PATH" && \
            log_success "Defconfig sorted" || \
            log_error "Failed to sort defconfig"
    }
    
    log_success "Defconfig updated: $DEFCONFIG_PATH"
    pause
}

show_main_menu() {
    clear
    echo -e "${LBLUE}=============================================="
    echo "      CyberEdge Kernel Configuration Tool     "
    echo "=============================================="
    echo -e "${NC}"
    
    local current_kernel=$(detect_kernel_version)
    [ -n "$current_kernel" ] && echo -e "${GREEN}Detected kernel: $current_kernel${NC}\n"
    
    echo -e "${YELLOW}Select an operation:${NC}"
}

show_operation_menu() {
    local options=(
        "Modify kernel defconfig"
        "Apply kernel patches"
        "Both: Patches then defconfig"
        "Exit"
    )
    
    show_main_menu
    
    select opt in "${options[@]}"; do
        case $REPLY in
            1) modify_defconfig; break ;;
            2) patch_kernel; break ;;
            3) 
                patch_kernel && modify_defconfig
                break ;;
            4) 
                echo -e "\n${GREEN}Goodbye!${NC}"
                exit 0 ;;
            *) 
                log_error "Invalid option"
                echo ;;
        esac
    done
}

# Main execution
[[ ! -d "arch" || ! -d "kernel" ]] && {
    log_error "This doesn't appear to be a kernel source directory"
    exit 1
}

# Command line arguments
if [ $# -gt 0 ]; then
    case "$1" in
        "defconfig"|"config") modify_defconfig ;;
        "patch"|"patches") patch_kernel ;;
        *) 
            log_error "Invalid argument: $1"
            echo "Usage: $0 [defconfig|patch]"
            exit 1 ;;
    esac
    exit 0
fi

# Interactive mode
while true; do
    show_operation_menu
    ask "Perform another operation?" "N" || {
        echo -e "\n${GREEN}Script completed.${NC}"
        exit 0
    }
done
