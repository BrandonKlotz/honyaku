#!/usr/bin/env ruby
require 'yaml'
require 'open3'

def parse_diff_additions(diff_output)
  added_lines = []
  diff_output.each_line do |line|
    if line.start_with?('+') && !line.start_with?('+++')
      added_lines << line[1..-1]
    end
  end
  added_lines
end

def parse_yaml_fragment(lines)
  # Try to build a valid YAML structure from the lines
  yaml_content = "ja:\n"
  current_indent = 0
  
  lines.each do |line|
    next if line.strip.empty?
    
    # Count leading spaces
    indent = line[/\A */].size
    
    yaml_content += line
  end
  
  begin
    YAML.load(yaml_content)
  rescue
    {}
  end
end

def extract_keys_from_hash(hash, prefix = '')
  keys = []
  
  hash.each do |key, value|
    full_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
    
    if value.is_a?(Hash)
      keys.concat(extract_keys_from_hash(value, full_key))
    else
      keys << full_key
    end
  end
  
  keys
end

# Main execution
if ARGV.length < 2
  puts "Usage: ruby extract_new_keys_from_diff.rb <ja_file> <en_file> [commit]"
  puts "Example: ruby extract_new_keys_from_diff.rb config/locales/ja/file.ja.yml config/locales/en/file.en.yml HEAD~1"
  exit 1
end

ja_file = ARGV[0]
en_file = ARGV[1]
commit = ARGV[2] || 'HEAD~1'

begin
  # Get the diff
  diff_output, status = Open3.capture2("git diff #{commit} #{ja_file}")
  
  if status.success?
    # Parse additions from diff
    added_lines = parse_diff_additions(diff_output)
    
    # Load the English file to check existing keys
    en_content = YAML.load_file(en_file)
    en_keys = extract_keys_from_hash(en_content)
    
    # Process added lines to find new keys
    new_content = {}
    current_path = []
    
    added_lines.each do |line|
      stripped = line.strip
      next if stripped.empty?
      
      # Calculate indent level
      indent = line[/\A */].size / 2
      
      # Adjust current path based on indent
      current_path = current_path[0...indent]
      
      if line =~ /^(\s*)([^:]+):\s*(.*)$/
        key = $2.strip
        value = $3.strip
        
        # Build full key path
        current_path << key
        full_key = current_path[1..-1].join('.')  # Skip 'ja' prefix
        
        # Check if this key exists in English
        if !en_keys.include?(full_key) && !value.empty? && value != '' && !value.end_with?(':')
          puts "#{full_key}: #{value}"
        end
        
        # Pop if this was a leaf node
        current_path.pop unless value.empty? || value.end_with?(':')
      end
    end
  else
    puts "Error running git diff: #{diff_output}"
    exit 1
  end
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace
  exit 1
end