require_relative 'yaml_ast_parser'
require_relative 'yaml_formatter'

module Honyaku
  class YamlMerger
    def initialize(target_yaml_content = nil)
      if target_yaml_content
        @target_content = target_yaml_content
        @target_lines = target_yaml_content.lines
        @parser = YamlAstParser.new(target_yaml_content)
        @ast_nodes = @parser.parse
        @formatter = YamlFormatter.new(@ast_nodes, @target_lines)
      end
    end

    def merge_keys(target_yaml_content, new_keys_with_values, locale)
      # Initialize with the target content
      @target_content = target_yaml_content
      @target_lines = target_yaml_content.lines
      @parser = YamlAstParser.new(target_yaml_content)
      @ast_nodes = @parser.parse
      @formatter = YamlFormatter.new(@ast_nodes, @target_lines)
      
      # Call the existing merge_new_keys method
      merge_new_keys(new_keys_with_values)
    end

    def merge_new_keys(new_keys_with_values)
      result_lines = @target_lines.dup
      
      # Sort keys to ensure proper nesting order
      sorted_keys = new_keys_with_values.keys.sort
      
      sorted_keys.each do |key_path|
        translated_value = new_keys_with_values[key_path]
        
        # Skip if key already exists (might have been added as parent)
        next if key_already_exists?(key_path, result_lines)
        
        insert_position = find_optimal_insert_position(key_path)
        formatted_entry = format_new_entry(key_path, translated_value, insert_position)
        
        result_lines.insert(insert_position[:line_number], formatted_entry)
      end
      
      result_lines.join
    end

    def key_already_exists?(key_path, lines)
      lines.any? { |line| line.match(/^\s*#{Regexp.escape(key_path.split('.').last)}:\s*/) }
    end

    private

    def find_optimal_insert_position(key_path)
      key_parts = key_path.split('.')
      
      # Try to find the most specific parent context
      parent_context = find_parent_context(key_parts)
      
      if parent_context
        # Insert after the parent context
        insert_after_parent(parent_context, key_parts.last)
      else
        # Fall back to inserting at the end of the appropriate section
        insert_at_section_end(key_parts)
      end
    end

    def find_parent_context(key_parts)
      # Work backwards from the full key path to find the deepest existing parent
      (key_parts.length - 1).downto(1) do |i|
        parent_path = key_parts[0...i].join('.')
        
        parent_node = @ast_nodes.find { |node| matches_key_path?(node.key, parent_path) }
        return parent_node if parent_node
      end
      
      nil
    end

    def matches_key_path?(node_key, target_path)
      return false unless node_key && target_path
      
      # Handle both direct matches and nested key paths
      node_key == target_path || node_key.start_with?("#{target_path}.")
    end

    def insert_after_parent(parent_node, new_key)
      # Find the last child of this parent
      parent_indent = parent_node.indent
      target_indent = parent_indent + @formatter.detect_indent_style[:size]
      
      # Look for the last line that belongs to this parent
      last_child_line = find_last_child_line(parent_node)
      
      {
        line_number: last_child_line + 1,
        indent: target_indent,
        context: parent_node
      }
    end

    def find_last_child_line(parent_node)
      parent_line = parent_node.line_number
      parent_indent = parent_node.indent
      
      # Start from the parent line and look for the last child
      last_line = parent_line
      
      ((parent_line + 1)...@target_lines.length).each do |i|
        line = @target_lines[i]
        next if line.strip.empty? || line.strip.start_with?('#')
        
        line_indent = line.match(/^(\s*)/)[1].length
        
        # If we've reached a line with equal or less indentation, we've found the boundary
        if line_indent <= parent_indent
          break
        end
        
        last_line = i
      end
      
      last_line
    end

    def insert_at_section_end(key_parts)
      # Find the appropriate section based on the first key part
      section_key = key_parts.first
      
      section_node = @ast_nodes.find { |node| node.key == section_key }
      
      if section_node
        last_line = find_last_child_line(section_node)
        target_indent = determine_target_indent(key_parts, section_node)
        
        {
          line_number: last_line + 1,
          indent: target_indent,
          context: section_node
        }
      else
        # Insert at the end of the file
        {
          line_number: @target_lines.length,
          indent: 0,
          context: nil
        }
      end
    end

    def determine_target_indent(key_parts, section_node)
      base_indent = section_node.indent
      indent_size = @formatter.detect_indent_style[:size]
      
      # Each nested level adds one indent
      nesting_level = key_parts.length - 1
      base_indent + (nesting_level * indent_size)
    end

    def format_new_entry(key_path, translated_value, insert_position)
      key_parts = key_path.split('.')
      final_key = key_parts.last
      
      # Create nested structure if needed
      if key_parts.length > 1
        format_nested_entry(key_parts, translated_value, insert_position)
      else
        format_simple_entry(final_key, translated_value, insert_position)
      end
    end

    def format_nested_entry(key_parts, translated_value, insert_position)
      lines = []
      current_indent = insert_position[:indent]
      indent_size = @formatter.detect_indent_style[:size]
      
      # Build the nested structure
      key_parts.each_with_index do |key, index|
        is_last = index == key_parts.length - 1
        
        if is_last
          # This is the final key with the actual value
          formatted = @formatter.format_new_key(key, translated_value, current_indent, insert_position[:line_number])
          lines << formatted[:line]
        else
          # This is a parent key that will contain children
          formatted = @formatter.format_new_key(key, nil, current_indent, insert_position[:line_number])
          lines << formatted[:line]
        end
        
        current_indent += indent_size
      end
      
      lines.join("\n") + "\n"
    end

    def format_simple_entry(key, translated_value, insert_position)
      formatted = @formatter.format_new_key(key, translated_value, insert_position[:indent], insert_position[:line_number])
      formatted[:line] + "\n"
    end

    def preserve_existing_formatting(line)
      # Check if the line has special formatting we should preserve
      has_anchor = line.include?('&')
      has_alias = line.include?('*')
      has_multiline = line.include?('|') || line.include?('>')
      
      {
        has_anchor: has_anchor,
        has_alias: has_alias,
        has_multiline: has_multiline,
        raw_line: line
      }
    end

    def build_nested_structure(key_parts, value, base_indent, indent_size)
      structure = {}
      current = structure
      
      key_parts[0..-2].each do |key|
        current[key] = {}
        current = current[key]
      end
      
      current[key_parts.last] = value
      structure
    end

    def extract_existing_keys
      existing_keys = Set.new
      
      @ast_nodes.each do |node|
        next unless node.key
        
        # Add both the direct key and any nested paths
        existing_keys.add(node.key)
        
        # If this is a nested key, add all parent paths too
        if node.key.include?('.')
          parts = node.key.split('.')
          (1...parts.length).each do |i|
            parent_path = parts[0...i].join('.')
            existing_keys.add(parent_path)
          end
        end
      end
      
      existing_keys
    end

    def key_exists?(key_path)
      existing_keys = extract_existing_keys
      existing_keys.include?(key_path)
    end

    def find_insertion_point_for_key(key_path)
      # Find the best place to insert a new key based on alphabetical order
      # and existing structure
      
      key_parts = key_path.split('.')
      section = key_parts.first
      
      # Find all keys in the same section
      section_keys = @ast_nodes.select { |node| 
        node.key && node.key.start_with?("#{section}.")
      }.map(&:key).sort
      
      # Find where this key would fit alphabetically
      insertion_index = section_keys.bsearch_index { |k| k > key_path }
      
      if insertion_index
        # Insert before this key
        target_node = @ast_nodes.find { |node| node.key == section_keys[insertion_index] }
        target_node.line_number
      else
        # Insert at the end of the section
        section_node = @ast_nodes.find { |node| node.key == section }
        section_node ? find_last_child_line(section_node) + 1 : @target_lines.length
      end
    end
  end
end