require "thor"
require "yaml"
require "fileutils"
require "honyaku/translator"
require "honyaku/yaml_ast_parser"
require "honyaku/yaml_formatter"
require "honyaku/yaml_merger"
require "honyaku/key_extractor"

module Honyaku
  class CLI < Thor
    desc "translate LOCALE", "Translate your application into the specified locale"
    long_desc <<-LONGDESC
      Translates YAML files from one locale to another using OpenAI.

      Examples:
        # Translate a specific file from English to Japanese
        $ honyaku translate ja --path config/locales/en.yml

        # Translate all files in a directory from English to Spanish
        $ honyaku translate es --path config/locales

        # Translate using GPT-4 for higher accuracy
        $ honyaku translate de --model gpt-4 --path config/locales/en.yml
    LONGDESC
    method_option :from, aliases: "-f", desc: "Source locale (defaults to en)"
    method_option :path, aliases: "-p", desc: "Path to YAML file or directory (defaults to config/locales)"
    method_option :model, 
                 aliases: "-m", 
                 desc: "Specify which AI model to use (defaults to gpt-4, use gpt-3.5-turbo for faster but less accurate translations)"
    method_option :backup, aliases: "-b", type: :boolean, desc: "Create .bak files before modifying"
    method_option :force, type: :boolean, desc: "Retranslate files even if target is newer than source"
    method_option :incremental, aliases: "-i", type: :boolean, desc: "Only translate new keys while preserving YAML formatting"
    method_option :new_keys_only, aliases: "-n", type: :boolean, desc: "Only translate keys that don't exist in the target file"
    def translate(locale)
      api_key = ENV["HONYAKU_OPENAI_API_KEY"] || ENV["OPENAI_API_KEY"]
      unless api_key
        puts "❌ Please set either HONYAKU_OPENAI_API_KEY or OPENAI_API_KEY environment variable"
        exit 1
      end

      source_locale = options[:from] || "en"
      path = options[:path] || "config/locales"
      model = options[:model] || "gpt-4"

      # Check if the source path exists
      unless File.exist?(path)
        puts "❌ Source path not found: #{path}"
        puts "   Please check that the file or directory exists"
        exit 1
      end

      # Find all .honyakurules files from root to current path
      rules = find_translation_rules(path, locale)
      if rules.any?
        puts "📋 Found #{rules.length} translation rule file(s):"
        rules.each do |rule|
          prefix = rule[:locale_specific] ? "🌐" : "📝"
          puts "   #{prefix} #{rule[:path]}"
        end
      end

      puts "🌏 Translating from #{source_locale} to #{locale}..."
      puts "📂 Processing files in #{path}..."

      # Translation mode messages
      if options[:new_keys_only]
        puts "🆕 New keys only mode: translating only keys that don't exist in target"
      elsif options[:incremental]
        puts "📝 Incremental mode: translating new and untranslated keys"
      end

      translator = Translator.new(model: model, translation_rules: rules)
      
      if File.file?(path)
        process_file(path, translator, source_locale, locale)
      else
        files = Dir.glob("#{path}/**/*.yml")
        if files.empty?
          puts "❌ No YAML files found in: #{path}"
          puts "   Make sure your path contains .yml files"
          exit 1
        end
        files.each do |file|
          process_file(file, translator, source_locale, locale)
        end
      end

      puts "✅ Translation complete!"
    end

    desc "fix PATH", "Fix YAML formatting issues in translated files"
    long_desc <<-LONGDESC
      Fixes common YAML formatting issues in translated files, such as:
      - Adding quotes around values that start with %{variable}
      - Fixing spacing in interpolation variables
      - Preserving YAML references and anchors
      - Maintaining proper indentation

      Examples:
        # Fix a specific file
        $ honyaku fix config/locales/ja/courses.ja.yml

        # Fix all YAML files in a directory
        $ honyaku fix config/locales/ja
    LONGDESC
    method_option :model, aliases: "-m", desc: "Specify which AI model to use (defaults to gpt-3.5-turbo)"
    method_option :backup, aliases: "-b", type: :boolean, desc: "Create .bak files before modifying"
    def fix(path)
      api_key = ENV["HONYAKU_OPENAI_API_KEY"] || ENV["OPENAI_API_KEY"]
      unless api_key
        puts "❌ Please set either HONYAKU_OPENAI_API_KEY or OPENAI_API_KEY environment variable"
        exit 1
      end

      model = options[:model] || "gpt-3.5-turbo"
      
      puts "🔧 Fixing YAML formatting issues..."
      puts "📂 Processing files in #{path}..."

      fixer = Translator.new(model: model)
      
      if File.file?(path)
        fix_file(path, fixer)
      else
        Dir.glob("#{path}/**/*.yml").each do |file|
          fix_file(file, fixer)
        end
      end

      puts "✅ Fixes complete!"
    end

    desc "version", "Show Honyaku version"
    def version
      puts "Honyaku v#{Honyaku::VERSION}"
    end

    private

    def find_translation_rules(start_path, target_locale = nil)
      rules = []
      
      # Start from the directory containing the YAML file/directory
      current_path = File.expand_path(start_path)
      
      # First check the current working directory
      if File.exist?('.honyakurules')
        rules << {
          path: File.expand_path('.honyakurules'),
          content: File.read('.honyakurules').strip
        }
      end
      
      # Check for locale-specific rules in current directory
      if target_locale && File.exist?(".honyakurules.#{target_locale}")
        rules << {
          path: File.expand_path(".honyakurules.#{target_locale}"),
          content: File.read(".honyakurules.#{target_locale}").strip,
          locale_specific: true
        }
      end
      
      # Walk up the directory tree from the YAML path
      while current_path != '/' && current_path != Dir.pwd
        # Check for general rules
        rules_file = File.join(current_path, '.honyakurules')
        if File.exist?(rules_file)
          rules << {
            path: rules_file,
            content: File.read(rules_file).strip
          }
        end
        
        # Check for locale-specific rules
        if target_locale
          locale_rules_file = File.join(current_path, ".honyakurules.#{target_locale}")
          if File.exist?(locale_rules_file)
            rules << {
              path: locale_rules_file,
              content: File.read(locale_rules_file).strip,
              locale_specific: true
            }
          end
        end
        
        current_path = File.dirname(current_path)
      end
      
      # Reverse to maintain root-to-local order, but ensure locale-specific rules come after general rules
      rules.reverse.partition { |r| !r[:locale_specific] }.flatten
    end

    def process_file(file_path, translator, source_locale, target_locale)
      # Check if this is a source locale file we should translate
      source_pattern = /#{source_locale}(\/|\.yml)/
      return unless file_path =~ source_pattern

      # Generate the target filename
      target_file = file_path.gsub(source_pattern, "#{target_locale}\\1")

      # Only skip if target exists AND is newer (unless --force is used)
      if File.exist?(target_file) && !options[:force]
        source_time = get_last_modified_time(file_path)
        target_time = get_last_modified_time(target_file)

        if target_time && source_time && target_time > source_time
          # Check if source has new keys that aren't in target
          if has_new_keys?(file_path, target_file)
            puts "🔄 Found new keys in #{file_path}, updating translation..."
          else
            puts "⏭️  Skipping #{file_path} - translation is up to date"
            return
          end
        end
      end

      puts "📝 Processing #{file_path}..."
      
      begin
        attempts = 0
        max_attempts = 3
        
        loop do
          attempts += 1
          begin
            if (options[:incremental] || options[:new_keys_only]) && File.exist?(target_file)
              if options[:new_keys_only]
                translated_content = process_new_keys_only_translation(file_path, target_file, translator, source_locale, target_locale)
              else
                translated_content = process_incremental_translation(file_path, target_file, translator, source_locale, target_locale)
              end
            else
              translated_content = translator.translate_hash(file_path, source_locale, target_locale)
            end
          rescue => e
            puts "❌ Translation failed: #{e.message}"
            break
          end
          
          # Don't proceed if translation failed
          if !translated_content || translated_content.strip.empty?
            puts "❌ Translation failed - no content generated"
            break
          end

          # Create directory and write file only if we have valid content
          FileUtils.mkdir_p(File.dirname(target_file))
          
          # Backup if requested
          if options[:backup] && File.exist?(target_file)
            backup_path = "#{target_file}.bak"
            FileUtils.cp(target_file, backup_path)
          end
          
          # Write the translated content
          File.write(target_file, translated_content)
          puts "✨ Created #{target_file}"
          
          # Automatically fix any YAML issues
          puts "🔧 Checking for YAML issues..."
          begin
            fixed_content = translator.fix_yaml(target_file)
            if fixed_content != translated_content
              if options[:backup] && !File.exist?("#{target_file}.bak")
                FileUtils.cp(target_file, "#{target_file}.bak")
              end
              
              File.write(target_file, fixed_content)
              puts "✨ Fixed YAML formatting issues"
            end
            break # Success! Exit the loop
          rescue => e
            if e.message.include?("needs retranslation") && attempts < max_attempts
              puts "⚠️  Translation attempt #{attempts} produced invalid YAML, retrying..."
              # Clean up the file before retrying
              File.unlink(target_file) if File.exist?(target_file)
              next
            else
              # Clean up and re-raise
              File.unlink(target_file) if File.exist?(target_file)
              raise e
            end
          end
        end
      rescue => e
        puts "❌ Error processing #{file_path}: #{e.message}"
        # Ensure file is cleaned up if it was created
        File.unlink(target_file) if File.exist?(target_file)
      end
    end

    def fix_file(file_path, fixer)
      puts "🔧 Fixing #{file_path}..."
      
      begin
        # Backup if requested
        if options[:backup]
          backup_path = "#{file_path}.bak"
          FileUtils.cp(file_path, backup_path)
          puts "📑 Created backup at #{backup_path}"
        end

        fixed_content = fixer.fix_yaml(file_path)
        File.write(file_path, fixed_content)
        puts "✨ Fixed #{file_path}"
      rescue => e
        puts "❌ Error fixing #{file_path}: #{e.message}"
      end
    end

    def get_last_modified_time(file_path)
      times = []
      
      # Get git timestamp if available
      if git_time = get_git_modified_time(file_path)
        times << git_time
      end
      
      # Get filesystem timestamp
      if File.exist?(file_path)
        times << File.mtime(file_path)
      end
      
      # Return the newest timestamp (or nil if no timestamps found)
      times.max
    end

    def get_git_modified_time(file_path)
      return nil unless system("git rev-parse --is-inside-work-tree > /dev/null 2>&1")
      
      time_str = `git log -1 --format=%cd --date=iso -- #{file_path} 2>/dev/null`.strip
      return nil if time_str.empty?
      
      Time.parse(time_str)
    rescue
      nil
    end

    def has_new_keys?(source_file, target_file)
      begin
        source_data = YAML.safe_load(File.read(source_file), aliases: true)
        target_data = YAML.safe_load(File.read(target_file), aliases: true)
        
        # Extract keys from the nested locale content (skip top-level locale keys)
        source_keys = []
        target_keys = []
        
        # For each top-level locale, extract its nested keys
        source_data.each do |locale, content|
          source_keys.concat(extract_all_keys(content)) if content.is_a?(Hash)
        end
        
        target_data.each do |locale, content|
          target_keys.concat(extract_all_keys(content)) if content.is_a?(Hash)
        end
        
        # Check if source has keys that target doesn't have
        new_keys = source_keys - target_keys
        new_keys.any?
      rescue => e
        # If we can't parse either file, err on the side of caution and retranslate
        puts "⚠️  Unable to compare keys (#{e.message}), will retranslate"
        true
      end
    end

    def extract_all_keys(data, prefix = "")
      keys = []
      
      case data
      when Hash
        data.each do |key, value|
          current_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
          if value.is_a?(Hash) || value.is_a?(Array)
            # Only recurse for nested structures, don't include intermediate keys
            keys.concat(extract_all_keys(value, current_key))
          else
            # This is a leaf node - add it as a translatable key
            keys << current_key
          end
        end
      when Array
        data.each_with_index do |value, index|
          current_key = "#{prefix}[#{index}]"
          if value.is_a?(Hash) || value.is_a?(Array)
            keys.concat(extract_all_keys(value, current_key))
          else
            keys << current_key
          end
        end
      end
      
      keys
    end


    def process_new_keys_only_translation(source_file, target_file, translator, source_locale, target_locale)
      puts "🔄 Using new keys only translation..."
      
      begin
        # Use KeyExtractor to find truly new keys
        extractor = KeyExtractor.new(source_file, target_file)
        new_keys = extractor.extract_new_keys(source_locale, target_locale)
        
        if new_keys.empty?
          puts "✅ No new keys found - target file is up to date"
          # Return the existing target file content
          return File.read(target_file) if File.exist?(target_file)
          # If target doesn't exist yet, do full translation
          return translator.translate_hash(source_file, source_locale, target_locale)
        end
        
        puts "📋 Found #{new_keys.length} new keys to translate"
        
        # Load existing target content
        target_content = File.exist?(target_file) ? File.read(target_file) : ""
        target_data = File.exist?(target_file) ? YAML.safe_load(target_content, aliases: true) : {}
        
        # Batch translate all new keys in a single request
        translated_new_keys = batch_translate_keys(new_keys, translator, source_locale, target_locale)
        
        puts "✅ Translated #{translated_new_keys.length} new keys"
        
        # Merge the new translations into the target structure
        merged_content = merge_new_translations(target_data, translated_new_keys, target_locale)
        
        # Convert back to YAML
        merged_content.to_yaml
        
      rescue => e
        puts "⚠️  New keys only translation failed (#{e.message}), falling back to full translation"
        translator.translate_hash(source_file, source_locale, target_locale)
      end
    end

    def process_incremental_translation(source_file, target_file, translator, source_locale, target_locale)
      puts "🔄 Using incremental translation (new and untranslated keys)..."
      
      begin
        # Use KeyExtractor to find both new keys and keys needing translation
        extractor = KeyExtractor.new(source_file, target_file)
        new_keys = extractor.extract_new_keys(source_locale, target_locale)
        keys_needing_translation = extractor.extract_keys_needing_translation(source_locale, target_locale)
        
        # Combine both sets of keys
        all_keys_to_translate = new_keys.merge(keys_needing_translation)
        
        if all_keys_to_translate.empty?
          puts "✅ No keys need translation - target file is up to date"
          # Return the existing target file content
          return File.read(target_file) if File.exist?(target_file)
          # If target doesn't exist yet, do full translation
          return translator.translate_hash(source_file, source_locale, target_locale)
        end
        
        puts "📋 Found #{all_keys_to_translate.length} keys to translate (#{new_keys.length} new, #{keys_needing_translation.length} untranslated)"
        
        # Load existing target content
        target_content = File.exist?(target_file) ? File.read(target_file) : ""
        target_data = File.exist?(target_file) ? YAML.safe_load(target_content, aliases: true) : {}
        
        # Batch translate all keys in a single request
        translated_keys = batch_translate_keys(all_keys_to_translate, translator, source_locale, target_locale)
        
        puts "✅ Translated #{translated_keys.length} keys"
        
        # Merge the translations into the target structure
        merged_content = merge_new_translations(target_data, translated_keys, target_locale)
        
        # Convert back to YAML
        merged_content.to_yaml
        
      rescue => e
        puts "⚠️  Incremental translation failed (#{e.message}), falling back to full translation"
        translator.translate_hash(source_file, source_locale, target_locale)
      end
    end

    def has_complex_yaml_features?(content)
      # Check for YAML features that would be broken by line-by-line replacement
      content.include?('&') ||      # Anchors
      content.include?('*') ||      # Aliases  
      content.include?('|') ||      # Literal block scalars
      content.include?('>') ||      # Folded block scalars
      content.match?(/^\s*-\s/)     # Arrays (could be complex)
    end

    def get_nested_value(data, key_path)
      keys = key_path.split('.')
      current = data
      
      keys.each do |key|
        if current.is_a?(Hash)
          # Handle array indices in key paths
          if key.include?('[') && key.include?(']')
            base_key = key.split('[').first
            index = key.match(/\[(\d+)\]/)[1].to_i
            current = current[base_key]
            return nil unless current.is_a?(Array) && current[index]
            current = current[index]
          else
            current = current[key]
          end
        else
          return nil
        end
        
        return nil unless current
      end
      
      current
    end



















    def create_mini_yaml_for_key(key_path, value, locale)
      # Create a minimal YAML structure for translation
      yaml_content = "#{locale}:\n"
      indent = "  "
      
      key_parts = key_path.split('.')
      key_parts.each_with_index do |part, index|
        if index == key_parts.length - 1
          # Last part - add the value
          yaml_content += "#{indent}#{part}: #{value.inspect}\n"
        else
          # Intermediate part - add nested structure
          yaml_content += "#{indent}#{part}:\n"
          indent += "  "
        end
      end
      
      yaml_content
    end

    def extract_translated_value_from_yaml(translated_yaml, key_path, target_locale)
      begin
        data = YAML.safe_load(translated_yaml)
        return nil unless data && data[target_locale]
        
        # Navigate through the nested structure
        get_nested_value(data[target_locale], key_path)
      rescue => e
        puts "⚠️  Failed to extract translated value for #{key_path}: #{e.message}"
        nil
      end
    end

    def merge_new_translations(existing_data, new_translations, target_locale)
      # Ensure the target locale exists in the data
      existing_data[target_locale] ||= {}
      
      # Merge each new translation into the existing structure
      new_translations.each do |key_path, value|
        set_nested_value(existing_data[target_locale], key_path, value)
      end
      
      existing_data
    end

    def batch_translate_keys(keys_to_translate, translator, source_locale, target_locale)
      return {} if keys_to_translate.empty?
      
      # Filter out non-string values
      translatable_keys = keys_to_translate.select { |_, value| value.is_a?(String) && !value.strip.empty? }
      
      if translatable_keys.empty?
        puts "⚠️  No translatable string values found"
        return {}
      end
      
      puts "🔄 Batch translating #{translatable_keys.length} keys..."
      
      begin
        # Create a single YAML structure with all keys
        batch_yaml = create_batch_yaml(translatable_keys, source_locale)
        
        # Translate the entire batch in one request
        translated_yaml = translator.translate_yaml_content(batch_yaml, source_locale, target_locale)
        
        # Extract individual translated values
        extract_batch_translations(translated_yaml, translatable_keys.keys, target_locale)
      rescue => e
        puts "⚠️  Batch translation failed (#{e.message}), falling back to individual translations"
        fallback_individual_translations(translatable_keys, translator, source_locale, target_locale)
      end
    end

    def create_batch_yaml(keys_hash, source_locale)
      yaml_content = "#{source_locale}:\n"
      
      keys_hash.each do |key_path, value|
        # Create nested structure for each key
        key_parts = key_path.split('.')
        
        # Build the nested YAML structure
        temp_structure = {}
        current = temp_structure
        
        key_parts[0..-2].each do |part|
          current[part] = {}
          current = current[part]
        end
        current[key_parts.last] = value
        
        # Convert the structure to YAML and merge it
        yaml_content = merge_yaml_structures(yaml_content, temp_structure, source_locale)
      end
      
      yaml_content
    end

    def merge_yaml_structures(existing_yaml, new_structure, locale)
      # Parse existing YAML
      existing_data = YAML.safe_load(existing_yaml) || {}
      existing_data[locale] ||= {}
      
      # Deep merge the new structure
      deep_merge_hash(existing_data[locale], new_structure)
      
      # Convert back to YAML
      existing_data.to_yaml
    end

    def deep_merge_hash(target, source)
      source.each do |key, value|
        if target[key].is_a?(Hash) && value.is_a?(Hash)
          deep_merge_hash(target[key], value)
        else
          target[key] = value
        end
      end
      target
    end

    def extract_batch_translations(translated_yaml, key_paths, target_locale)
      translated_keys = {}
      
      begin
        data = YAML.safe_load(translated_yaml)
        return {} unless data && data[target_locale]
        
        key_paths.each do |key_path|
          translated_value = get_nested_value(data[target_locale], key_path)
          translated_keys[key_path] = translated_value if translated_value
        end
      rescue => e
        puts "⚠️  Failed to extract batch translations: #{e.message}"
      end
      
      translated_keys
    end

    def fallback_individual_translations(keys_hash, translator, source_locale, target_locale)
      translated_keys = {}
      
      keys_hash.each do |key_path, value|
        puts "🔄 Translating key individually: #{key_path}"
        
        begin
          # Create a minimal YAML structure for this key
          mini_yaml = create_mini_yaml_for_key(key_path, value, source_locale)
          
          # Translate the mini YAML
          translated_yaml = translator.translate_yaml_content(mini_yaml, source_locale, target_locale)
          
          # Extract the translated value
          translated_value = extract_translated_value_from_yaml(translated_yaml, key_path, target_locale)
          
          translated_keys[key_path] = translated_value if translated_value
        rescue => e
          puts "⚠️  Error translating #{key_path}: #{e.message}"
        end
      end
      
      translated_keys
    end

    def set_nested_value(hash, key_path, value)
      keys = key_path.split('.')
      current = hash
      
      keys[0..-2].each do |key|
        # Handle array indices in key paths
        if key.include?('[') && key.include?(']')
          base_key = key.split('[').first
          index = key.match(/\[(\d+)\]/)[1].to_i
          
          current[base_key] ||= []
          current = current[base_key]
          current[index] ||= {}
          current = current[index]
        else
          current[key] ||= {}
          current = current[key]
        end
      end
      
      # Set the final value
      final_key = keys.last
      if final_key.include?('[') && final_key.include?(']')
        base_key = final_key.split('[').first
        index = final_key.match(/\[(\d+)\]/)[1].to_i
        current[base_key] ||= []
        current[base_key][index] = value
      else
        current[final_key] = value
      end
    end













    desc "status", "Show translation status for all locales"
    def status
      puts "📊 Translation Status:"
      # Status reporting logic will go here
    end

    def self.exit_on_failure?
      true
    end
  end
end 