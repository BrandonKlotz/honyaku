#!/usr/bin/env ruby
require 'yaml'

def extract_keys_with_values(hash, prefix = '')
  result = {}
  
  hash.each do |key, value|
    full_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
    
    if value.is_a?(Hash)
      result.merge!(extract_keys_with_values(value, full_key))
    else
      result[full_key] = value
    end
  end
  
  result
end

def get_new_keys_from_diff(ja_file, en_file)
  # Load YAML files
  ja_content = YAML.load_file(ja_file)
  en_content = YAML.load_file(en_file)
  
  # Extract all keys with their values
  ja_keys = extract_keys_with_values(ja_content['ja'])
  en_keys = extract_keys_with_values(en_content['en'])
  
  # Find keys that exist in Japanese but not in English
  new_keys = {}
  ja_keys.each do |key, value|
    unless en_keys.key?(key)
      new_keys[key] = value
    end
  end
  
  new_keys
end

def rebuild_nested_hash(flat_hash)
  result = {}
  
  flat_hash.each do |key, value|
    parts = key.split('.')
    current = result
    
    parts[0..-2].each do |part|
      current[part] ||= {}
      current = current[part]
    end
    
    current[parts.last] = value
  end
  
  { 'ja' => result }
end

# Main execution
if ARGV.length < 2
  puts "Usage: ruby extract_new_keys.rb <ja_file> <en_file>"
  exit 1
end

ja_file = ARGV[0]
en_file = ARGV[1]

begin
  new_keys = get_new_keys_from_diff(ja_file, en_file)
  
  if new_keys.empty?
    puts "No new keys found in the Japanese file."
  else
    puts "Found #{new_keys.length} new keys:"
    puts "=" * 50
    
    # Rebuild nested structure for better display
    nested = rebuild_nested_hash(new_keys)
    puts nested.to_yaml
  end
rescue => e
  puts "Error: #{e.message}"
  exit 1
end