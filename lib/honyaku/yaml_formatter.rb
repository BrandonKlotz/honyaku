module Honyaku
  class YamlFormatter
    def initialize(ast_nodes, original_lines)
      @ast_nodes = ast_nodes
      @original_lines = original_lines
      @style_patterns = analyze_formatting_patterns
    end

    def format_new_key(key, value, target_indent, insert_after_line = nil)
      # Determine the formatting style based on surrounding context
      style = determine_key_style(key, target_indent, insert_after_line)
      
      formatted_line = build_formatted_line(key, value, style)
      
      {
        line: formatted_line,
        indent: target_indent,
        style: style
      }
    end

    def detect_indent_style
      @style_patterns[:indent_style]
    end

    def detect_quote_style
      @style_patterns[:quote_style]
    end

    def detect_spacing_style
      @style_patterns[:spacing_style]
    end

    private

    def analyze_formatting_patterns
      patterns = {
        indent_style: detect_indentation_pattern,
        quote_style: detect_quotation_pattern,
        spacing_style: detect_spacing_pattern,
        line_ending_style: detect_line_ending_pattern
      }
      
      patterns
    end

    def detect_indentation_pattern
      indent_counts = {}
      
      @original_lines.each do |line|
        next if line.strip.empty? || line.strip.start_with?('#')
        
        indent = line.match(/^(\s*)/)[1]
        next if indent.empty?
        
        if indent.include?("\t")
          indent_counts[:tabs] = (indent_counts[:tabs] || 0) + 1
        else
          spaces = indent.length
          indent_counts[spaces] = (indent_counts[spaces] || 0) + 1
        end
      end
      
      # Determine if tabs or spaces are used
      if indent_counts[:tabs] && indent_counts[:tabs] > 0
        return { type: :tabs, size: 1 }
      end
      
      # Find the most common space count that's not 0
      common_spaces = indent_counts.reject { |k, v| k == :tabs || k == 0 }.max_by { |k, v| v }
      
      if common_spaces
        return { type: :spaces, size: common_spaces[0] }
      end
      
      # Default to 2 spaces
      { type: :spaces, size: 2 }
    end

    def detect_quotation_pattern
      quote_patterns = { single: 0, double: 0, none: 0 }
      
      @original_lines.each do |line|
        next unless line.include?(':')
        
        if match = line.match(/:\s*(['"])(.*?)\1/)
          quote_type = match[1] == '"' ? :double : :single
          quote_patterns[quote_type] += 1
        elsif line.match(/:\s*[^'"\s]/)
          quote_patterns[:none] += 1
        end
      end
      
      quote_patterns.max_by { |k, v| v }[0]
    end

    def detect_spacing_pattern
      spacing_patterns = { colon_space: 0, no_colon_space: 0 }
      
      @original_lines.each do |line|
        if line.match(/:\s/)
          spacing_patterns[:colon_space] += 1
        elsif line.match(/:[^\s]/)
          spacing_patterns[:no_colon_space] += 1
        end
      end
      
      spacing_patterns[:colon_space] > spacing_patterns[:no_colon_space] ? :space_after_colon : :no_space_after_colon
    end

    def detect_line_ending_pattern
      endings = { unix: 0, windows: 0 }
      
      @original_lines.each do |line|
        if line.end_with?("\r\n")
          endings[:windows] += 1
        elsif line.end_with?("\n")
          endings[:unix] += 1
        end
      end
      
      endings[:windows] > endings[:unix] ? :windows : :unix
    end

    def determine_key_style(key, target_indent, insert_after_line)
      # Look at surrounding lines to determine style
      context_lines = get_context_lines(insert_after_line, target_indent)
      
      # Use the most common style from context
      if context_lines.any?
        analyze_context_style(context_lines)
      else
        # Fall back to document-wide patterns
        @style_patterns
      end
    end

    def get_context_lines(insert_after_line, target_indent)
      return [] unless insert_after_line
      
      context = []
      start_line = [insert_after_line - 2, 0].max
      end_line = [insert_after_line + 2, @original_lines.length - 1].min
      
      (start_line..end_line).each do |i|
        line = @original_lines[i]
        next if line.strip.empty? || line.strip.start_with?('#')
        
        line_indent = line.match(/^(\s*)/)[1].length
        # Only consider lines at similar indentation levels
        if (line_indent - target_indent).abs <= 2
          context << line
        end
      end
      
      context
    end

    def analyze_context_style(context_lines)
      # Analyze the context lines to determine local style preferences
      local_patterns = {
        indent_style: @style_patterns[:indent_style], # Keep document-wide indent style
        quote_style: detect_local_quote_style(context_lines),
        spacing_style: detect_local_spacing_style(context_lines),
        line_ending_style: @style_patterns[:line_ending_style]
      }
      
      local_patterns
    end

    def detect_local_quote_style(lines)
      quote_patterns = { single: 0, double: 0, none: 0 }
      
      lines.each do |line|
        next unless line.include?(':')
        
        if match = line.match(/:\s*(['"])(.*?)\1/)
          quote_type = match[1] == '"' ? :double : :single
          quote_patterns[quote_type] += 1
        elsif line.match(/:\s*[^'"\s]/)
          quote_patterns[:none] += 1
        end
      end
      
      # Return the most common pattern, or fall back to document-wide
      local_max = quote_patterns.max_by { |k, v| v }
      local_max[1] > 0 ? local_max[0] : @style_patterns[:quote_style]
    end

    def detect_local_spacing_style(lines)
      spacing_patterns = { colon_space: 0, no_colon_space: 0 }
      
      lines.each do |line|
        if line.match(/:\s/)
          spacing_patterns[:colon_space] += 1
        elsif line.match(/:[^\s]/)
          spacing_patterns[:no_colon_space] += 1
        end
      end
      
      # Return the most common pattern, or fall back to document-wide
      if spacing_patterns[:colon_space] > 0 || spacing_patterns[:no_colon_space] > 0
        spacing_patterns[:colon_space] > spacing_patterns[:no_colon_space] ? :space_after_colon : :no_space_after_colon
      else
        @style_patterns[:spacing_style]
      end
    end

    def build_formatted_line(key, value, style)
      # Build the indentation
      indent_str = build_indent_string(style[:indent_style])
      
      # Build the key part
      key_part = key.to_s
      
      # Build the separator
      separator = style[:spacing_style] == :space_after_colon ? ': ' : ':'
      
      # Build the value part
      value_part = format_value(value, style)
      
      "#{indent_str}#{key_part}#{separator}#{value_part}"
    end

    def build_indent_string(indent_style)
      case indent_style[:type]
      when :tabs
        "\t" * (indent_style[:size] || 1)
      when :spaces
        " " * (indent_style[:size] || 2)
      else
        "  " # Default to 2 spaces
      end
    end

    def format_value(value, style)
      return "" if value.nil? || value.to_s.strip.empty?
      
      value_str = value.to_s
      
      # Handle special YAML constructs
      if is_multiline_string?(value_str)
        format_multiline_string(value_str, style)
      elsif is_alias_reference?(value_str)
        value_str # Keep aliases as-is
      elsif needs_quoting?(value_str)
        quote_char = style[:quote_style] == :single ? "'" : '"'
        "#{quote_char}#{escape_value(value_str, quote_char)}#{quote_char}"
      else
        value_str
      end
    end

    def is_multiline_string?(value)
      value.include?("\n") || value.length > 80
    end

    def is_alias_reference?(value)
      value.start_with?('*')
    end

    def format_multiline_string(value, style)
      # For now, use literal style for multiline strings
      # In a full implementation, we'd preserve the original style
      "|\n" + value.split("\n").map { |line| "  #{line}" }.join("\n")
    end

    def needs_quoting?(value)
      # Values that start with special characters need quoting
      value.match?(/^[%&*!|>@`]/) ||
      # Values that contain special YAML characters
      value.include?(':') ||
      value.include?('#') ||
      value.include?('[') ||
      value.include?(']') ||
      value.include?('{') ||
      value.include?('}') ||
      # Values that look like numbers/booleans but should be strings
      value.match?(/^\d+$/) ||
      value.match?(/^(true|false|null|~)$/i)
    end

    def escape_value(value, quote_char)
      if quote_char == '"'
        value.gsub(/["\\]/, '\\\\\\&')
      else
        value.gsub(/['\\]/, '\\\\\\&')
      end
    end
  end
end