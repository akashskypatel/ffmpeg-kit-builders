#!/bin/bash

# A script to update SOURCE_ID in source.sh to the latest GitHub release/tag.
# It can update all libraries or a specific one provided via command-line arguments.
# Authentication can be provided via arguments or interactive prompts.

# --- Configuration ---
SOURCE_FILE="source.sh"
BACKUP_FILE="${SOURCE_FILE}.bak"

# --- Functions ---

# Function to display usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Updates library sources in '$SOURCE_FILE' to their latest GitHub release tag."
    echo ""
    echo "Options:"
    echo "  -l, --library <name>   Specify a single library to update. If omitted, all libraries will be processed."
    echo "  -u, --user <username>  Your GitHub username for API authentication."
    echo "  -t, --token <token>    Your GitHub Personal Access Token (PAT)."
    echo "  -h, --help             Display this help message and exit."
    echo ""
    echo "Example (update all libraries, prompts for credentials):"
    echo "  $0"
    echo ""
    echo "Example (update a single library, provide credentials as arguments):"
    echo "  $0 --library dav1d --user your_username --token your_pat"
}

# Function for portable in-place sed (works on both GNU/Linux and BSD/macOS)
sedi() {
    if [[ $(uname) == 'Darwin' ]]; then
        # macOS/BSD sed requires an extension for the backup file.
        sed -i '' "$@"
    else
        # GNU sed does not require an extension.
        sed -i "$@"
    fi
}

# --- Main Script ---

# 1. Parse Command-Line Arguments
SPECIFIC_LIBRARY=""
GH_USER=""
GH_TOKEN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--user)
            GH_USER="$2"
            shift 2
            ;;
        -t|--token)
            GH_TOKEN="$2"
            shift 2
            ;;
        -l|--library)
            SPECIFIC_LIBRARY="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# 2. Check if the source file exists
if [ ! -f "$SOURCE_FILE" ]; then
    echo "Error: '$SOURCE_FILE' not found in the current directory."
    echo "Please run this script in the same directory as your source.sh file."
    exit 1
fi

# 3. Handle GitHub credentials
if [ -z "$GH_USER" ] || [ -z "$GH_TOKEN" ]; then
    echo "GitHub credentials not provided via arguments. Please enter them now."
    echo "A Personal Access Token (PAT) is recommended: https://github.com/settings/tokens"
    read -p "GitHub Username: " GH_USER_PROMPT
    read -s -p "GitHub Personal Access Token: " GH_TOKEN_PROMPT
    echo ""

    GH_USER=${GH_USER:-$GH_USER_PROMPT}
    GH_TOKEN=${GH_TOKEN:-$GH_TOKEN_PROMPT}
fi

if [ -z "$GH_USER" ] || [ -z "$GH_TOKEN" ]; then
    echo "Error: GitHub username and Personal Access Token are required. Exiting."
    exit 1
fi

# 4. Create a backup of the original file
echo "Backing up '$SOURCE_FILE' to '$BACKUP_FILE'..."
cp "$SOURCE_FILE" "$BACKUP_FILE"

# 5. Determine which libraries to process
all_libraries=$(awk '/case \$1 in/,/esac/ { if ($0 ~ /^\s+[a-zA-Z0-9._-]+\)/) { sub(/^\s+/, ""); sub(/\).*/, ""); print } }' "$SOURCE_FILE")

if [ -z "$all_libraries" ]; then
    echo "Error: Could not find any library definitions in '$SOURCE_FILE'. Exiting."
    exit 1
fi

libraries_to_process=""
if [ -n "$SPECIFIC_LIBRARY" ]; then
    if ! echo "$all_libraries" | grep -q -w "$SPECIFIC_LIBRARY"; then
        echo "Error: Library '$SPECIFIC_LIBRARY' not found in '$SOURCE_FILE'."
        exit 1
    fi
    libraries_to_process="$SPECIFIC_LIBRARY"
    echo "--- Processing single library: $SPECIFIC_LIBRARY ---"
else
    libraries_to_process="$all_libraries"
    echo "--- Processing all libraries ---"
fi

# 6. Loop through each library to check for updates
for library in $libraries_to_process; do
    echo "Processing '$library'..."

    block=$(awk "/^  ${library}\)/,/;;/" "$SOURCE_FILE")

    repo_url=$(echo "$block" | sed -n -E 's/.*SOURCE_REPO_URL="([^"]+)".*/\1/p')
    current_id=$(echo "$block" | sed -n -E 's/.*SOURCE_ID="([^"]+)".*/\1/p')
    current_type=$(echo "$block" | sed -n -E 's/.*SOURCE_TYPE="([^"]+)".*/\1/p')

    if [ -z "$repo_url" ]; then
        echo "  - Skipping: No SOURCE_REPO_URL found for '$library'."
        continue
    fi
    
    if [[ ! "$repo_url" =~ ^https://github.com/ ]]; then
        sedi "/^\s*${library}[)]/,/;;/ s/SOURCE_TYPE=\"[^\"]*\"/SOURCE_TYPE=\"DOWNLOAD\"/" "$SOURCE_FILE"
        echo "  - Updated SOURCE_TYPE to DOWNLOAD for non-GitHub repository."
        echo "  - Skipping: Not a GitHub repository."
        continue
    fi

    owner_repo=$(echo "$repo_url" | sed -E 's|https://github.com/([^/]+)/([^/.]+).*|\1/\2|')
    owner=$(echo "$owner_repo" | cut -d'/' -f1)
    repo=$(echo "$owner_repo" | cut -d'/' -f2)

    if [ -z "$owner" ] || [ -z "$repo" ]; then
        echo "  - Skipping: Could not parse owner/repo from URL '$repo_url'."
        continue
    fi

    # Check for releases first
    releases_api_url="https://api.github.com/repos/$owner/$repo/releases/latest"
    releases_response=$(curl -s -u "$GH_USER:$GH_TOKEN" "$releases_api_url")
    releases_curl_exit_code=$?

    if [ $releases_curl_exit_code -ne 0 ]; then
        echo "  - Skipping: curl command failed with exit code $releases_curl_exit_code."
        continue
    fi
    
    # Check if we got a valid response
    if echo "$releases_response" | grep -q '"message":'; then
        message=$(echo "$releases_response" | sed -n -E 's/.*"message": "([^"]+)".*/\1/p')
        echo "  - Releases API returned: $message"
        has_releases=false
    else
        has_releases=true
    fi

    if [ "$has_releases" = true ]; then
        # GitHub repo → Has releases → Has tag
        latest_release_tag=$(echo "$releases_response" | grep '"tag_name":' | head -n 1 | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
        latest_release_name=$(echo "$releases_response" | grep '"name":' | head -n 1 | sed -E 's/.*"name": "([^"]+)".*/\1/')
        
        echo "  - Found latest release: '$latest_release_name' with tag: '$latest_release_tag'"
        
        if [ "$latest_release_tag" != "$current_id" ] || [ "$current_type" != "TAG" ]; then
            echo "  - UPDATE FOUND: '$current_id' -> '$latest_release_tag' (RELEASE TAG)"
            
            # Escape special characters
            escaped_tag=$(printf '%s\n' "$latest_release_tag" | sed 's/[[\.*^$()+?{|]/\\&/g')
            
            sedi "/^\s*${library}[)]/,/;;/ s/SOURCE_ID=\"[^\"]*\"/SOURCE_ID=\"${escaped_tag}\"/" "$SOURCE_FILE"
            sedi "/^\s*${library}[)]/,/;;/ s/SOURCE_TYPE=\"[^\"]*\"/SOURCE_TYPE=\"TAG\"/" "$SOURCE_FILE"
            
            echo "  - Successfully updated to latest release tag."
        else
            echo "  - Already up to date with latest release tag (Current: '$current_id')."
        fi
    else
        # GitHub repo → No releases → No tags
        master_download_url="https://github.com/$owner/$repo"
        
        echo "  - No releases or tags found, using master branch"
        
        escaped_url=$(printf '%s\n' "$master_download_url" | sed 's/[[\.*^$()+?{|]/\\&/g')
        
        sedi "/^\s*${library}[)]/,/;;/ s|SOURCE_REPO_URL=\"[^\"]*\"|SOURCE_REPO_URL=\"${escaped_url}\"|" "$SOURCE_FILE"
        sedi "/^\s*${library}[)]/,/;;/ s/SOURCE_ID=\"[^\"]*\"/SOURCE_ID=\"master\"/" "$SOURCE_FILE"
        sedi "/^\s*${library}[)]/,/;;/ s/SOURCE_TYPE=\"[^\"]*\"/SOURCE_TYPE=\"BRANCH\"/" "$SOURCE_FILE"
        
        echo "  - Updated to master branch."
    fi

done

echo "---"
echo "Update script finished successfully."
echo "A backup of the original file is saved as '$BACKUP_FILE'."