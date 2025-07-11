# frozen_string_literal: true

require "test_helper"

class TestCopyReplaceApproach < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    
    # English source file with formatting, anchors, aliases
    @source_content = <<~YAML
      en: &en_locale
        navigation:
          dashboard: "Dashboard"
          settings: 'Settings'
          profile: Profile
          # This is a navigation comment
        forms: &forms_section
          login:
            title: "Login"
            submit: 'Sign In'
          signup:
            title: "Sign Up"
            submit: Create Account
        messages:
          welcome: Welcome
          goodbye: Goodbye
        shared:
          buttons: *forms_section
    YAML
    
    # Existing Japanese target file (missing some keys)
    @target_content = <<~YAML
      ja:
        navigation:
          dashboard: "ダッシュボード"
          settings: '設定'
        forms:
          login:
            title: "ログイン"
            submit: 'サインイン'
        messages:
          welcome: ようこそ
    YAML
    
    @source_file = File.join(@temp_dir, "source.en.yml")
    @target_file = File.join(@temp_dir, "source.ja.yml")
    
    File.write(@source_file, @source_content)
    File.write(@target_file, @target_content)
  end
  
  def teardown
    FileUtils.rm_rf(@temp_dir)
  end
  
  def test_copy_source_structure_with_target_locale
    cli = Honyaku::CLI.new
    
    result = cli.send(:copy_source_structure_with_target_locale, @source_content, "en", "ja")
    
    puts "Original English content:"
    puts @source_content
    puts "\nAfter locale replacement:"
    puts result
    
    # Check that it preserves everything but changes locale
    assert_includes result, "ja: &en_locale", "Should preserve anchor but change locale"
    assert_includes result, "&forms_section", "Should preserve forms anchor"
    assert_includes result, "*forms_section", "Should preserve alias reference"
    assert_includes result, "# This is a navigation comment", "Should preserve comments"
    assert_includes result, '"Dashboard"', "Should preserve double quotes"
    assert_includes result, "'Settings'", "Should preserve single quotes"
    assert_includes result, "Profile", "Should preserve unquoted values"
  end
  
  def test_replace_with_existing_translations
    cli = Honyaku::CLI.new
    
    # First copy the structure
    copied_content = cli.send(:copy_source_structure_with_target_locale, @source_content, "en", "ja")
    
    # Parse existing target data
    target_data = YAML.safe_load(@target_content, aliases: true)
    
    # Replace with existing translations
    result = cli.send(:replace_with_existing_translations, copied_content, target_data, "ja")
    
    puts "After replacing with existing translations:"
    puts result
    
    # Check that existing translations were substituted while preserving formatting
    assert_includes result, '"ダッシュボード"', "Should replace dashboard with Japanese, preserving quotes"
    assert_includes result, "'設定'", "Should replace settings with Japanese, preserving single quotes"
    assert_includes result, '"ログイン"', "Should replace login title"
    assert_includes result, "'サインイン'", "Should replace login submit"
    assert_includes result, "ようこそ", "Should replace welcome"
    
    # Check that untranslated keys remain in English
    assert_includes result, "Profile", "Should keep profile in English (not yet translated)"
    assert_includes result, "Sign Up", "Should keep signup title in English"
    assert_includes result, "Goodbye", "Should keep goodbye in English"
  end
  
  def test_find_remaining_english_keys
    cli = Honyaku::CLI.new
    
    # Create content with mixed English/Japanese
    mixed_content = <<~YAML
      ja:
        navigation:
          dashboard: "ダッシュボード"
          settings: '設定'
          profile: Profile
        forms:
          login:
            title: "ログイン"
          signup:
            title: "Sign Up"
        messages:
          goodbye: Goodbye
    YAML
    
    english_keys = cli.send(:find_remaining_english_keys, mixed_content, "ja")
    
    puts "Found remaining English keys:"
    english_keys.each do |key_info|
      puts "  #{key_info[:key_path]}: #{key_info[:value]}"
    end
    
    # Should find the keys that are still in English
    english_key_paths = english_keys.map { |k| k[:key_path] }
    assert_includes english_key_paths, "navigation.profile"
    assert_includes english_key_paths, "forms.signup.title"
    assert_includes english_key_paths, "messages.goodbye"
    
    # Should not include Japanese keys
    refute_includes english_key_paths, "navigation.dashboard"
    refute_includes english_key_paths, "navigation.settings"
    refute_includes english_key_paths, "forms.login.title"
  end
  
  def test_end_to_end_copy_replace_approach
    # Mock the translator for remaining keys
    translator = Minitest::Mock.new
    
    # Only expect translations for the actual remaining English keys we detected
    translator.expect(:translate_yaml_content, "ja:\n  navigation:\n    profile: プロフィール\n", [String, "en", "ja"])
    translator.expect(:translate_yaml_content, "ja:\n  forms:\n    signup:\n      title: サインアップ\n", [String, "en", "ja"]) 
    translator.expect(:translate_yaml_content, "ja:\n  forms:\n    signup:\n      submit: アカウント作成\n", [String, "en", "ja"])
    translator.expect(:translate_yaml_content, "ja:\n  messages:\n    goodbye: さようなら\n", [String, "en", "ja"])
    
    cli = Honyaku::CLI.new
    result = cli.send(:process_incremental_translation, @source_file, @target_file, translator, "en", "ja")
    
    puts "Final result:"
    puts result
    
    # Check that the result preserves the English file structure
    assert_includes result, "ja: &en_locale", "Should preserve anchor structure"
    assert_includes result, "&forms_section", "Should preserve forms anchor"
    assert_includes result, "*forms_section", "Should preserve alias reference"
    assert_includes result, "# This is a navigation comment", "Should preserve comments"
    
    # Check that existing translations were used
    assert_includes result, '"ダッシュボード"', "Should use existing dashboard translation"
    assert_includes result, "'設定'", "Should use existing settings translation"
    assert_includes result, '"ログイン"', "Should use existing login translation"
    
    # Check that new translations were added
    assert_includes result, "プロフィール", "Should add new profile translation"
    assert_includes result, "サインアップ", "Should add new signup translation"
    assert_includes result, "さようなら", "Should add new goodbye translation"
    
    # Verify the structure is parseable and correct
    result_data = YAML.safe_load(result, aliases: true)
    assert_equal "ダッシュボード", result_data["ja"]["navigation"]["dashboard"]
    assert_equal "プロフィール", result_data["ja"]["navigation"]["profile"]
    assert_equal "サインアップ", result_data["ja"]["forms"]["signup"]["title"]
    
    translator.verify
  end
end