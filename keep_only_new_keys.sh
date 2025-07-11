#!/bin/bash

# Usage: ./keep_only_new_keys.sh <target_file> <english_file> [commit]
# Example: ./keep_only_new_keys.sh config/locales/ja/funnel_workflow_builder.ja.yml config/locales/en/funnel_workflow_builder.en.yml HEAD~1

TARGET_FILE=$1
ENGLISH_FILE=$2
COMMIT=${3:-HEAD}

if [ -z "$TARGET_FILE" ] || [ -z "$ENGLISH_FILE" ]; then
    echo "Usage: $0 <target_file> <english_file> [commit]"
    echo "Example: $0 config/locales/ja/file.ja.yml config/locales/en/file.en.yml HEAD~1"
    exit 1
fi

echo "🔄 Keeping only new keys in $TARGET_FILE..."

# Step 1: Get the original version of the target file
echo "📥 Getting original version from $COMMIT..."
ORIGINAL_CONTENT=$(git show $COMMIT:$TARGET_FILE 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ Could not find $TARGET_FILE at $COMMIT"
    exit 1
fi

# Step 2: Extract new keys using our existing function
echo "🔍 Finding new keys..."
NEW_KEYS_OUTPUT=$(extract_new_keys $TARGET_FILE $ENGLISH_FILE $COMMIT)

if [ -z "$NEW_KEYS_OUTPUT" ]; then
    echo "✅ No new keys found. Resetting file to original version."
    echo "$ORIGINAL_CONTENT" > $TARGET_FILE
    exit 0
fi

# Step 3: Extract the key names from the output
echo "📋 Processing new keys..."
NEW_KEY_NAMES=$(echo "$NEW_KEYS_OUTPUT" | grep -E "^[a-zA-Z_][^:]*:" | cut -d: -f1 | sort -u)

if [ -z "$NEW_KEY_NAMES" ]; then
    echo "✅ No valid new keys found. Resetting file to original version."
    echo "$ORIGINAL_CONTENT" > $TARGET_FILE
    exit 0
fi

echo "Found keys to preserve:"
echo "$NEW_KEY_NAMES" | sed 's/^/  - /'

# Step 4: Create a temporary file with the original content
TEMP_ORIGINAL=$(mktemp)
echo "$ORIGINAL_CONTENT" > $TEMP_ORIGINAL

# Step 5: Extract only the new key lines from the current file
TEMP_NEW_LINES=$(mktemp)
CURRENT_FILE_CONTENT=$(cat $TARGET_FILE)

# Process each new key and extract its lines from the current file
echo "$NEW_KEY_NAMES" | while read -r key_name; do
    if [ -n "$key_name" ]; then
        # Extract the line(s) for this key from the current file
        # This handles both simple keys and nested structures
        grep -E "^[[:space:]]*${key_name}:" $TARGET_FILE >> $TEMP_NEW_LINES 2>/dev/null
    fi
done

# Step 6: Merge the original content with the new lines
echo "🔀 Merging original content with new keys..."

# Create the final content by starting with original and adding new keys
cp $TEMP_ORIGINAL $TARGET_FILE

# Add new lines at the end for now (you might want to place them more strategically)
if [ -s $TEMP_NEW_LINES ]; then
    echo "" >> $TARGET_FILE
    echo "# New keys added:" >> $TARGET_FILE
    cat $TEMP_NEW_LINES >> $TARGET_FILE
fi

# Cleanup
rm -f $TEMP_ORIGINAL $TEMP_NEW_LINES

echo "✅ Successfully kept only new keys in $TARGET_FILE"
echo "🔍 Review the changes with: git diff $TARGET_FILE"