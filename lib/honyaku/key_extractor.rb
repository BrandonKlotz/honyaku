require "yaml"
require "set"

module Honyaku
  class KeyExtractor
    def initialize(source_file, target_file)
      @source_file = source_file
      @target_file = target_file
    end

    # Extract keys that exist in source but not in target
    def extract_new_keys(source_locale, target_locale)
      source_content = load_yaml_file(@source_file)
      target_content = load_yaml_file(@target_file)
      
      # Extract all keys from both files
      source_keys = extract_all_keys(source_content[source_locale])
      target_keys = extract_all_keys(target_content[target_locale])
      
      # Find keys that exist in source but not in target
      new_keys = source_keys.keys.to_set - target_keys.keys.to_set
      
      # Return hash of new keys with their values
      new_keys_with_values = {}
      new_keys.each do |key|
        new_keys_with_values[key] = source_keys[key]
      end
      
      new_keys_with_values
    end

    # Extract keys that exist in target with source language values (need translation)
    def extract_keys_needing_translation(source_locale, target_locale)
      target_content = load_yaml_file(@target_file)
      
      keys_needing_translation = {}
      target_data = target_content[target_locale]
      
      if target_data
        extract_translatable_keys(target_data, keys_needing_translation, source_locale)
      end
      
      keys_needing_translation
    end

    private

    def load_yaml_file(file_path)
      return {} unless File.exist?(file_path)
      YAML.safe_load(File.read(file_path), aliases: true) || {}
    rescue => e
      puts "⚠️  Error loading YAML file #{file_path}: #{e.message}"
      {}
    end

    def extract_all_keys(data, prefix = "")
      keys = {}
      
      case data
      when Hash
        data.each do |key, value|
          current_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
          
          if value.is_a?(Hash)
            keys.merge!(extract_all_keys(value, current_key))
          elsif value.is_a?(Array)
            keys.merge!(extract_all_keys(value, current_key))
          else
            keys[current_key] = value
          end
        end
      when Array
        data.each_with_index do |value, index|
          current_key = "#{prefix}[#{index}]"
          if value.is_a?(Hash)
            keys.merge!(extract_all_keys(value, current_key))
          elsif value.is_a?(Array)
            keys.merge!(extract_all_keys(value, current_key))
          else
            keys[current_key] = value
          end
        end
      end
      
      keys
    end

    def extract_translatable_keys(data, result, source_locale, prefix = "")
      case data
      when Hash
        data.each do |key, value|
          current_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
          
          if value.is_a?(Hash)
            extract_translatable_keys(value, result, source_locale, current_key)
          elsif value.is_a?(String) && needs_translation?(value, source_locale)
            result[current_key] = value
          end
        end
      when Array
        data.each_with_index do |value, index|
          current_key = "#{prefix}[#{index}]"
          if value.is_a?(Hash)
            extract_translatable_keys(value, result, source_locale, current_key)
          elsif value.is_a?(String) && needs_translation?(value, source_locale)
            result[current_key] = value
          end
        end
      end
    end

    def needs_translation?(text, source_locale)
      return false if text.nil? || text.strip.empty?
      
      # Remove quotes to check the actual value
      clean_text = text.gsub(/^["']|["']$/, '')
      
      # Skip if the value is clearly not a translatable string
      return false if clean_text.empty? || clean_text.match?(/^[&*]/)
      
      # Check if text is in source language
      case source_locale.downcase
      when 'en'
        is_english_text?(clean_text)
      when 'pt', 'pt-br', 'pt-pt'
        is_portuguese_text?(clean_text)
      when 'es'
        is_spanish_text?(clean_text)
      when 'fr'
        is_french_text?(clean_text)
      else
        # For other languages, use a generic Latin script detection
        is_latin_script_text?(clean_text)
      end
    end

    def is_english_text?(text)
      return false if text.length < 2
      
      ascii_letters = text.scan(/[A-Za-z]/).length
      non_latin_chars = count_non_latin_chars(text)
      
      return false if ascii_letters == 0
      
      # If there are non-Latin characters, English must be dominant
      if non_latin_chars > 0
        return ascii_letters >= non_latin_chars
      end
      
      # No non-Latin characters, check if it looks like English
      ascii_letters > text.length * 0.3
    end

    def is_portuguese_text?(text)
      return false if text.length < 2
      
      latin_letters = text.scan(/[A-Za-zÀ-ÿ]/).length
      non_latin_chars = count_non_latin_chars(text)
      
      return false if latin_letters == 0
      
      if non_latin_chars > 0
        return latin_letters >= non_latin_chars
      end
      
      # Check for Portuguese-specific patterns
      has_portuguese_markers = text.match?(/[ãõçáéíóúâêôàüñ]/) ||
                              text.match?(/\b(com|para|uma?|dos?|das?|não|são|está)\b/i)
      
      has_portuguese_markers || latin_letters > text.length * 0.3
    end

    def is_spanish_text?(text)
      return false if text.length < 2
      
      latin_letters = text.scan(/[A-Za-zÀ-ÿ]/).length
      non_latin_chars = count_non_latin_chars(text)
      
      return false if latin_letters == 0
      
      if non_latin_chars > 0
        return latin_letters >= non_latin_chars
      end
      
      # Check for Spanish-specific patterns
      has_spanish_markers = text.match?(/[ñáéíóúü¿¡]/) ||
                           text.match?(/\b(con|para|una?|los?|las?|del|que|está)\b/i)
      
      has_spanish_markers || latin_letters > text.length * 0.3
    end

    def is_french_text?(text)
      return false if text.length < 2
      
      latin_letters = text.scan(/[A-Za-zÀ-ÿ]/).length
      non_latin_chars = count_non_latin_chars(text)
      
      return false if latin_letters == 0
      
      if non_latin_chars > 0
        return latin_letters >= non_latin_chars
      end
      
      # Check for French-specific patterns
      has_french_markers = text.match?(/[àâäçéèêëïîôöùûüÿ]/) ||
                          text.match?(/\b(avec|pour|une?|les?|des?|que|est)\b/i)
      
      has_french_markers || latin_letters > text.length * 0.3
    end

    def is_latin_script_text?(text)
      return false if text.length < 2
      
      latin_letters = text.scan(/[A-Za-zÀ-ÿ]/).length
      non_latin_chars = count_non_latin_chars(text)
      
      return false if latin_letters == 0
      
      if non_latin_chars > 0
        return latin_letters >= non_latin_chars
      end
      
      latin_letters > text.length * 0.3
    end

    def count_non_latin_chars(text)
      # Count common non-Latin scripts
      japanese_chars = count_japanese_chars(text)
      chinese_chars = text.scan(/[\u4E00-\u9FFF]/).length
      korean_chars = text.scan(/[\uAC00-\uD7AF]/).length
      arabic_chars = text.scan(/[\u0600-\u06FF]/).length
      cyrillic_chars = text.scan(/[\u0400-\u04FF]/).length
      
      japanese_chars + chinese_chars + korean_chars + arabic_chars + cyrillic_chars
    end

    def count_japanese_chars(text)
      hiragana = text.scan(/[\u3040-\u309F]/).length
      katakana = text.scan(/[\u30A0-\u30FF]/).length
      kanji = text.scan(/[\u4E00-\u9FAF]/).length
      hiragana + katakana + kanji
    end
  end
end