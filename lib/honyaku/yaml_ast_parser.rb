require 'yaml'
require 'psych'

module Honyaku
  class YamlAstParser
    class ASTNode
      attr_accessor :key, :value, :type, :line_number, :column, :raw_text, :indent, :comment, :alias_ref, :anchor_name

      def initialize(key: nil, value: nil, type: :scalar, line_number: nil, column: nil, raw_text: nil, indent: 0, comment: nil, alias_ref: nil, anchor_name: nil)
        @key = key
        @value = value
        @type = type
        @line_number = line_number
        @column = column
        @raw_text = raw_text
        @indent = indent
        @comment = comment
        @alias_ref = alias_ref
        @anchor_name = anchor_name
      end

      def has_alias?
        !@alias_ref.nil?
      end

      def has_anchor?
        !@anchor_name.nil?
      end

      def is_mapping?
        @type == :mapping
      end

      def is_sequence?
        @type == :sequence
      end

      def is_scalar?
        @type == :scalar
      end
    end

    def initialize(yaml_content)
      @yaml_content = yaml_content
      @lines = yaml_content.lines
      @ast_nodes = []
      @line_metadata = {}
    end

    def parse
      begin
        # Parse with Psych to get the structure
        parsed_data = YAML.safe_load(@yaml_content, aliases: true)
        
        # Build our AST with formatting metadata
        build_ast_from_lines(parsed_data)
        
        @ast_nodes
      rescue => e
        raise "Failed to parse YAML: #{e.message}"
      end
    end

    def find_key_node(key_path)
      @ast_nodes.find { |node| node.key == key_path }
    end

    def get_line_metadata(line_number)
      @line_metadata[line_number] || {}
    end

    private

    def build_ast_from_lines(parsed_data)
      @lines.each_with_index do |line, index|
        line_number = index + 1
        analyze_line(line, line_number, parsed_data)
      end
    end

    def analyze_line(line, line_number, parsed_data)
      return if line.strip.empty? || line.strip.start_with?('#')

      indent = calculate_indent(line)
      
      # Check for YAML anchors and aliases
      anchor_match = line.match(/&(\w+)/)
      alias_match = line.match(/\*(\w+)/)
      
      # Check for multi-line indicators
      multiline_match = line.match(/[|>][-+]?/)
      
      # Check for array items
      array_match = line.match(/^(\s*)-\s*(.*)$/)
      
      # Check for key-value pairs
      if key_value_match = line.match(/^(\s*)([^:]+):\s*(.*)$/)
        key = key_value_match[2].strip
        value = key_value_match[3].strip
        
        # Determine node type with enhanced logic
        node_type = determine_node_type(value, line, line_number)

        # Extract comment if present
        comment = nil
        if comment_match = line.match(/#\s*(.+)$/)
          comment = comment_match[1].strip
        end

        node = ASTNode.new(
          key: key,
          value: value.empty? ? nil : value,
          type: node_type,
          line_number: line_number,
          column: key_value_match[1].length,
          raw_text: line.chomp,
          indent: indent,
          comment: comment,
          alias_ref: alias_match ? alias_match[1] : nil,
          anchor_name: anchor_match ? anchor_match[1] : nil
        )

        @ast_nodes << node
      elsif array_match
        # Handle array items
        value = array_match[2].strip
        
        node = ASTNode.new(
          key: nil,
          value: value,
          type: :sequence_item,
          line_number: line_number,
          column: array_match[1].length,
          raw_text: line.chomp,
          indent: indent,
          alias_ref: alias_match ? alias_match[1] : nil,
          anchor_name: anchor_match ? anchor_match[1] : nil
        )

        @ast_nodes << node
      end

      # Store line metadata with enhanced information
      @line_metadata[line_number] = {
        indent: indent,
        raw_text: line.chomp,
        has_anchor: !anchor_match.nil?,
        has_alias: !alias_match.nil?,
        has_multiline: !multiline_match.nil?,
        is_array_item: !array_match.nil?,
        anchor_name: anchor_match ? anchor_match[1] : nil,
        alias_name: alias_match ? alias_match[1] : nil,
        multiline_indicator: multiline_match ? multiline_match[0] : nil
      }
    end

    def determine_node_type(value, line, line_number)
      # Check for multi-line indicators
      if value == '|' || value == '>' || value =~ /[|>][-+]?$/
        return :multiline_scalar
      end
      
      # Check for array indicator
      if value.start_with?('-') || line.strip.start_with?('-')
        return :sequence
      end
      
      # Check for alias reference
      if value.start_with?('*')
        return :alias
      end
      
      # Check for anchor definition
      if value.include?('&')
        return :anchor
      end
      
      # Check if this starts a nested structure
      if value.empty?
        # Look ahead to see if next non-empty line is indented more
        next_line_number = line_number + 1
        while next_line_number < @lines.length
          next_line = @lines[next_line_number - 1] # Convert to 0-based index
          break if !next_line.strip.empty? && !next_line.strip.start_with?('#')
          next_line_number += 1
        end
        
        if next_line_number < @lines.length
          next_line = @lines[next_line_number - 1]
          next_indent = calculate_indent(next_line)
          current_indent = calculate_indent(line)
          
          if next_indent > current_indent
            return :mapping
          end
        end
      end
      
      # Default to scalar
      :scalar
    end

    def calculate_indent(line)
      line.match(/^(\s*)/)[1].length
    end

    def extract_nested_keys(data, prefix = "", current_indent = 0)
      keys = []
      
      case data
      when Hash
        data.each do |key, value|
          full_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
          keys << {
            key: full_key,
            value: value,
            indent: current_indent
          }
          
          if value.is_a?(Hash)
            keys.concat(extract_nested_keys(value, full_key, current_indent + 2))
          elsif value.is_a?(Array)
            value.each_with_index do |item, index|
              if item.is_a?(Hash)
                keys.concat(extract_nested_keys(item, "#{full_key}[#{index}]", current_indent + 2))
              end
            end
          end
        end
      when Array
        data.each_with_index do |item, index|
          if item.is_a?(Hash)
            keys.concat(extract_nested_keys(item, "#{prefix}[#{index}]", current_indent + 2))
          end
        end
      end
      
      keys
    end
  end
end