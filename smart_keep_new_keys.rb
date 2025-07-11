#!/usr/bin/env ruby

require 'yaml'
require 'open3'

def usage
  puts "Usage: #{$0} <target_file> <english_file> [commit]"
  puts "Example: #{$0} config/locales/ja/file.ja.yml config/locales/en/file.en.yml HEAD~1"
  exit 1
end

def get_new_keys(target_file, english_file, commit = 'HEAD')
  # Use the extract_new_keys function to get new keys
  output, status = Open3.capture2("extract_new_keys #{target_file} #{english_file} #{commit}")
  
  unless status.success?
    puts "❌ Failed to extract new keys"
    exit 1
  end
  
  new_keys = []
  
  # Parse the output to extract key names
  output.each_line do |line|
    # Match lines like "key_name: value" but not headers like "### section ###"
    if line.match(/^([a-zA-Z_][^:]*):/)
      key_name = $1.strip
      new_keys << key_name unless key_name.empty?
    end
  end
  
  new_keys.uniq
end

def get_original_content(file_path, commit)
  content, status = Open3.capture2("git show #{commit}:#{file_path}")
  
  unless status.success?
    puts "❌ Could not find #{file_path} at #{commit}"
    exit 1
  end
  
  content
end

def extract_key_with_context(file_content, key_name)
  lines = file_content.lines
  result_lines = []
  in_key_context = false
  key_indent = nil
  
  lines.each_with_index do |line, index|
    stripped = line.strip
    
    # Check if this line starts our target key
    if stripped.start_with?("#{key_name}:")
      in_key_context = true
      key_indent = line[/\A */].length
      result_lines << line
      next
    end
    
    # If we're in context, check if we should continue
    if in_key_context
      current_indent = line[/\A */].length
      
      # If we hit a line with equal or less indentation (and it's not empty/comment), we're done
      if !stripped.empty? && !stripped.start_with?('#') && current_indent <= key_indent
        break
      end
      
      # Include this line as part of the key's context
      result_lines << line
    end
  end
  
  result_lines
end

def merge_new_keys_into_yaml(original_content, current_content, new_key_names)
  # Parse both YAML files
  begin
    original_data = YAML.safe_load(original_content, aliases: true) || {}
    current_data = YAML.safe_load(current_content, aliases: true) || {}
  rescue => e
    puts "❌ YAML parsing error: #{e.message}"
    exit 1
  end
  
  # Get the locale key (e.g., 'ja', 'pt', etc.)
  locale_key = current_data.keys.first
  
  unless locale_key
    puts "❌ Could not determine locale from current file"
    exit 1
  end
  
  # Start with original data
  result_data = original_data.dup
  result_data[locale_key] ||= {}
  
  # Add only the new keys from current data
  new_key_names.each do |key_name|
    if current_data[locale_key] && current_data[locale_key].key?(key_name)
      result_data[locale_key][key_name] = current_data[locale_key][key_name]
      puts "✅ Added key: #{key_name}"
    end
  end
  
  result_data.to_yaml
end

# Main execution
usage if ARGV.length < 2

target_file = ARGV[0]
english_file = ARGV[1]
commit = ARGV[2] || 'HEAD'

puts "🔄 Keeping only new keys in #{target_file}..."

# Step 1: Get new keys
puts "🔍 Finding new keys..."
new_keys = get_new_keys(target_file, english_file, commit)

if new_keys.empty?
  puts "✅ No new keys found. Resetting file to original version."
  original_content = get_original_content(target_file, commit)
  File.write(target_file, original_content)
  exit 0
end

puts "📋 Found #{new_keys.length} new keys to preserve:"
new_keys.each { |key| puts "  - #{key}" }

# Step 2: Get original and current content
original_content = get_original_content(target_file, commit)
current_content = File.read(target_file)

# Step 3: Merge new keys into original structure
puts "🔀 Merging new keys into original structure..."
result_content = merge_new_keys_into_yaml(original_content, current_content, new_keys)

# Step 4: Write the result
File.write(target_file, result_content)

puts "✅ Successfully kept only new keys in #{target_file}"
puts "📊 Preserved #{new_keys.length} new keys"
puts "🔍 Review the changes with: git diff #{target_file}"