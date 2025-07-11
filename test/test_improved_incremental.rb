# frozen_string_literal: true

require "test_helper"

class TestImprovedIncremental < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
  end
  
  def teardown
    FileUtils.rm_rf(@temp_dir)
  end
  
  def test_complex_yaml_detection
    cli = Honyaku::CLI.new
    
    # Simple YAML should not be detected as complex
    simple_yaml = <<~YAML
      en:
        key1: "Value 1"
        key2: 'Value 2'
        section:
          nested: Simple value
    YAML
    
    assert_equal false, cli.send(:has_complex_yaml_features?, simple_yaml)
    
    # YAML with anchors should be detected as complex
    anchor_yaml = <<~YAML
      en: &en_locale
        key1: "Value 1"
        shared: &shared
          button: Save
    YAML
    
    assert_equal true, cli.send(:has_complex_yaml_features?, anchor_yaml)
    
    # YAML with aliases should be detected as complex
    alias_yaml = <<~YAML
      en:
        shared: &shared
          button: Save
        forms:
          buttons: *shared
    YAML
    
    assert_equal true, cli.send(:has_complex_yaml_features?, alias_yaml)
    
    # YAML with multiline strings should be detected as complex
    multiline_yaml = <<~YAML
      en:
        description: |
          This is a long
          multiline description
          that spans multiple lines
    YAML
    
    assert_equal true, cli.send(:has_complex_yaml_features?, multiline_yaml)
  end
  
  def test_source_language_detection
    cli = Honyaku::CLI.new
    
    # English detection
    assert_equal true, cli.send(:is_source_language_text?, "Hello World", "en")
    assert_equal true, cli.send(:is_source_language_text?, "Save changes", "en")
    assert_equal false, cli.send(:is_source_language_text?, "こんにちは", "en")
    
    # Portuguese detection
    assert_equal true, cli.send(:is_source_language_text?, "Olá mundo", "pt")
    assert_equal true, cli.send(:is_source_language_text?, "Salvar alterações", "pt")
    assert_equal true, cli.send(:is_source_language_text?, "Configuração", "pt")
    assert_equal true, cli.send(:is_source_language_text?, "não", "pt")  # Portuguese-specific
    assert_equal false, cli.send(:is_source_language_text?, "こんにちは", "pt")
    
    # Spanish detection
    assert_equal true, cli.send(:is_source_language_text?, "Hola mundo", "es")
    assert_equal true, cli.send(:is_source_language_text?, "Configuración", "es")
    assert_equal true, cli.send(:is_source_language_text?, "¿Cómo está?", "es")  # Spanish-specific
    assert_equal false, cli.send(:is_source_language_text?, "こんにちは", "es")
    
    # French detection
    assert_equal true, cli.send(:is_source_language_text?, "Bonjour monde", "fr")
    assert_equal true, cli.send(:is_source_language_text?, "Paramètres", "fr")
    assert_equal true, cli.send(:is_source_language_text?, "Français", "fr")  # French-specific
    assert_equal false, cli.send(:is_source_language_text?, "こんにちは", "fr")
    
    # Generic Latin script for other languages
    assert_equal true, cli.send(:is_source_language_text?, "Hello World", "de")  # German
    assert_equal true, cli.send(:is_source_language_text?, "Hallo Welt", "de")
    assert_equal false, cli.send(:is_source_language_text?, "こんにちは", "de")
    
    # Edge cases
    assert_equal false, cli.send(:is_source_language_text?, "123", "en")  # Numbers only
    assert_equal false, cli.send(:is_source_language_text?, "", "en")     # Empty
    assert_equal false, cli.send(:is_source_language_text?, "A", "en")    # Too short
  end
  
  def test_simple_yaml_uses_copy_replace_approach
    # Simple YAML without complex features
    source_content = <<~YAML
      en:
        navigation:
          dashboard: "Dashboard"
          profile: Profile
        messages:
          welcome: Welcome
          goodbye: Goodbye
    YAML
    
    target_content = <<~YAML
      ja:
        navigation:
          dashboard: "ダッシュボード"
        messages:
          welcome: ようこそ
    YAML
    
    source_file = File.join(@temp_dir, "simple.en.yml")
    target_file = File.join(@temp_dir, "simple.ja.yml")
    
    File.write(source_file, source_content)
    File.write(target_file, target_content)
    
    # Mock translator
    translator = Minitest::Mock.new
    translator.expect(:translate_yaml_content, "ja:\n  navigation:\n    profile: プロフィール\n", [String, "en", "ja"])
    translator.expect(:translate_yaml_content, "ja:\n  messages:\n    goodbye: さようなら\n", [String, "en", "ja"])
    
    cli = Honyaku::CLI.new
    result = cli.send(:process_incremental_translation, source_file, target_file, translator, "en", "ja")
    
    # Should preserve exact formatting and add translations
    assert_includes result, "ja:", "Should have correct locale"
    assert_includes result, '"ダッシュボード"', "Should preserve existing translation with quotes"
    assert_includes result, "プロフィール", "Should add new profile translation"
    assert_includes result, "さようなら", "Should add new goodbye translation"
    
    # Verify structure
    result_data = YAML.safe_load(result)
    assert_equal "ダッシュボード", result_data["ja"]["navigation"]["dashboard"]
    assert_equal "プロフィール", result_data["ja"]["navigation"]["profile"]
    assert_equal "ようこそ", result_data["ja"]["messages"]["welcome"]
    assert_equal "さようなら", result_data["ja"]["messages"]["goodbye"]
    
    translator.verify
  end
  
  def test_complex_yaml_uses_standard_approach
    # Complex YAML with anchors and aliases
    source_content = <<~YAML
      en: &en_locale
        shared: &shared_buttons
          save: "Save"
          cancel: Cancel
        forms:
          buttons: *shared_buttons
        messages:
          welcome: Welcome
          goodbye: Goodbye
    YAML
    
    target_content = <<~YAML
      ja:
        shared:
          save: "保存"
          cancel: キャンセル
        forms:
          buttons:
            save: "保存"
            cancel: キャンセル
        messages:
          welcome: ようこそ
    YAML
    
    source_file = File.join(@temp_dir, "complex.en.yml")
    target_file = File.join(@temp_dir, "complex.ja.yml")
    
    File.write(source_file, source_content)
    File.write(target_file, target_content)
    
    # Mock translator for new key
    translator = Minitest::Mock.new
    translator.expect(:translate_yaml_content, "ja:\n  messages:\n    goodbye: さようなら\n", [String, "en", "ja"])
    
    cli = Honyaku::CLI.new
    result = cli.send(:process_incremental_translation, source_file, target_file, translator, "en", "ja")
    
    # Should detect complex features and use standard approach
    # The exact output format may vary but structure should be correct
    result_data = YAML.safe_load(result, aliases: true)
    assert_equal "保存", result_data["ja"]["shared"]["save"]
    assert_equal "ようこそ", result_data["ja"]["messages"]["welcome"]
    assert_equal "さようなら", result_data["ja"]["messages"]["goodbye"]
    
    translator.verify
  end
end