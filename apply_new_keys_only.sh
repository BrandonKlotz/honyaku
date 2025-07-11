#!/bin/bash

# Apply only new keys from extract_new_keys output to a file
# Usage: ./apply_new_keys_only.sh <target_file> <english_file> [commit]

TARGET_FILE=$1
ENGLISH_FILE=$2
COMMIT=${3:-HEAD}

if [ -z "$TARGET_FILE" ] || [ -z "$ENGLISH_FILE" ]; then
    echo "Usage: $0 <target_file> <english_file> [commit]"
    echo "Example: $0 config/locales/ja/funnel_workflow_builder.ja.yml config/locales/en/funnel_workflow_builder.en.yml HEAD~1"
    exit 1
fi

echo "🔄 Applying only new keys to $TARGET_FILE..."

# Create backup
cp $TARGET_FILE ${TARGET_FILE}.backup
echo "💾 Created backup: ${TARGET_FILE}.backup"

# Get original version
echo "📥 Getting original version from $COMMIT..."
git show $COMMIT:$TARGET_FILE > ${TARGET_FILE}.original 2>/dev/null

if [ $? -ne 0 ]; then
    echo "❌ Could not find $TARGET_FILE at $COMMIT"
    rm -f ${TARGET_FILE}.backup ${TARGET_FILE}.original
    exit 1
fi

# Extract new keys and save to temp file
echo "🔍 Extracting new keys..."
extract_new_keys $TARGET_FILE $ENGLISH_FILE $COMMIT > ${TARGET_FILE}.new_keys

# Check if we found any new keys
if ! grep -q "Total new keys:" ${TARGET_FILE}.new_keys; then
    echo "✅ No new keys found. Restoring original version."
    cp ${TARGET_FILE}.original $TARGET_FILE
    rm -f ${TARGET_FILE}.backup ${TARGET_FILE}.original ${TARGET_FILE}.new_keys
    exit 0
fi

# Create Ruby script to merge only new keys
cat > ${TARGET_FILE}.merge.rb << 'EOF'
require 'yaml'

target_file = ARGV[0]
original_file = ARGV[1]
new_keys_file = ARGV[2]

# Load files
current_data = YAML.safe_load(File.read(target_file), aliases: true)
original_data = YAML.safe_load(File.read(original_file), aliases: true)
new_keys_output = File.read(new_keys_file)

# Get locale
locale = current_data.keys.first

# Parse new keys from the extract_new_keys output
new_keys = {}
current_section = nil

new_keys_output.each_line do |line|
  line = line.strip
  
  # Skip headers and empty lines
  next if line.empty? || line.start_with?('===') || line.start_with?('Extracting') || line.start_with?('Total new keys')
  
  # Handle section headers like "### AttachedWorkflowsSidebar ###"
  if line.match(/^### (.+) ###$/)
    current_section = $1
    next
  end
  
  # Handle key-value pairs
  if line.match(/^([^:]+):\s*(.+)$/)
    key = $1.strip
    value = $2.strip
    
    # Handle nested keys like "Sidebar.PageStepCard.attach_workflow: value"
    if key.include?('.')
      key_parts = key.split('.')
    else
      # Simple key under current section
      if current_section
        key_parts = [current_section, key]
      else
        key_parts = [key]
      end
    end
    
    # Store the key path and value
    new_keys[key_parts.join('.')] = value
  end
end

puts "Found #{new_keys.length} new keys to apply:"
new_keys.each { |k, v| puts "  #{k}: #{v}" }

# Start with original data
result_data = original_data.dup
result_data[locale] ||= {}

# Function to set nested value
def set_nested_value(hash, key_path, value)
  keys = key_path.split('.')
  current = hash
  
  keys[0..-2].each do |key|
    current[key] ||= {}
    current = current[key]
  end
  
  current[keys.last] = value
end

# Apply new keys
new_keys.each do |key_path, value|
  set_nested_value(result_data[locale], key_path, value)
  puts "✅ Applied: #{key_path}"
end

# Write result
File.write(target_file, result_data.to_yaml)
puts "✅ Successfully applied #{new_keys.length} new keys"
EOF

# Run the Ruby merge script
ruby ${TARGET_FILE}.merge.rb $TARGET_FILE ${TARGET_FILE}.original ${TARGET_FILE}.new_keys

# Clean up temporary files
rm -f ${TARGET_FILE}.original ${TARGET_FILE}.new_keys ${TARGET_FILE}.merge.rb

echo "🎉 Done! Original backed up to ${TARGET_FILE}.backup"
echo "🔍 Review changes with: git diff ${TARGET_FILE}"
echo "🗑️  Remove backup with: rm ${TARGET_FILE}.backup"