#!/bin/bash

# Usage: ./extract_new_keys.sh <ja_file> <en_file> [commit]
# Example: ./extract_new_keys.sh config/locales/ja/funnel_workflow_builder.ja.yml config/locales/en/funnel_workflow_builder.en.yml HEAD~1

JA_FILE=$1
EN_FILE=$2
COMMIT=${3:-HEAD~1}

if [ -z "$JA_FILE" ] || [ -z "$EN_FILE" ]; then
    echo "Usage: $0 <ja_file> <en_file> [commit]"
    exit 1
fi

echo "Extracting new keys from $JA_FILE that don't exist in $EN_FILE..."
echo "================================================"

# Extract all keys from the English file
ruby -ryaml -e "
def extract_keys(hash, prefix='')
  hash.flat_map do |k,v|
    key = prefix.empty? ? k.to_s : \"#{prefix}.#{k}\"
    v.is_a?(Hash) ? extract_keys(v, key) : key
  end
end
en = YAML.load_file('$EN_FILE')
puts extract_keys(en['en'])
" > /tmp/en_keys.txt

# Process git diff to find truly new keys
git diff $COMMIT $JA_FILE | ruby -ryaml -e "
en_keys = File.readlines('/tmp/en_keys.txt').map(&:strip)
current_path = []
added_content = []

STDIN.each_line do |line|
  next unless line.start_with?('+') && !line.start_with?('+++')
  
  line = line[1..-1]
  next if line.strip.empty?
  
  indent = line[/\A */].size / 2
  current_path = current_path[0...indent]
  
  if line =~ /^(\s*)([^:]+):\s*(.*)$/
    key = \$2.strip
    value = \$3.strip
    
    current_path << key
    full_key = current_path[1..-1].join('.')
    
    unless en_keys.include?(full_key) || value.empty? || value == ''
      added_content << \"#{current_path.join('.')}: #{value}\"
    end
    
    current_path.pop unless value.empty? || value.end_with?(':')
  end
end

# Group by top-level key for better output
grouped = {}
added_content.each do |line|
  if line =~ /^ja\.([^.]+)\./
    top_key = \$1
    grouped[top_key] ||= []
    grouped[top_key] << line
  end
end

grouped.each do |key, lines|
  puts \"\\n### #{key} ###\"
  lines.each { |l| puts l }
end
"

rm -f /tmp/en_keys.txt