# frozen_string_literal: true

require "test_helper"

class TestFormattingPreservation < Minitest::Test
  def setup
    # Target file with specific formatting, quotes, and aliases
    @target_content_with_formatting = <<~YAML
      ja: &ja_locale
        navigation:
          dashboard: "ダッシュボード"
          settings: 設定
        forms:
          login:
            title: 'ログイン'
            submit: "サインイン"
        messages:
          welcome: ようこそ
          # This is a comment that should be preserved
        shared: &shared_section
          buttons:
            save: "保存"
        # Reference to shared section
        other_area:
          shared_buttons: *shared_section
    YAML
    
    @temp_dir = Dir.mktmpdir
    @target_file = File.join(@temp_dir, "test.ja.yml")
    File.write(@target_file, @target_content_with_formatting)
  end
  
  def teardown
    FileUtils.rm_rf(@temp_dir)
  end
  
  def test_formatting_preservation_with_line_insertion
    # Test the new line-by-line insertion approach
    cli = Honyaku::CLI.new
    
    translated_keys = {
      "en.navigation.profile" => "プロフィール",
      "en.messages.goodbye" => "さようなら"
    }
    
    result = cli.send(:merge_keys_preserving_structure, @target_content_with_formatting, translated_keys, "ja")
    
    puts "Original content:"
    puts @target_content_with_formatting
    puts "\nResult with line-by-line insertion:"
    puts result
    
    # Check that formatting is preserved
    assert_includes result, "&ja_locale", "Should preserve anchor"
    assert_includes result, "&shared_section", "Should preserve shared anchor"
    assert_includes result, "*shared_section", "Should preserve alias reference"
    assert_includes result, "# This is a comment", "Should preserve comments"
    assert_includes result, "'ログイン'", "Should preserve single quotes"
    assert_includes result, "\"ダッシュボード\"", "Should preserve double quotes"
    
    # Check that new keys were added
    assert_includes result, "profile: ", "Should add profile key"
    assert_includes result, "goodbye: ", "Should add goodbye key"
    
    # Verify the structure is correct
    result_data = YAML.safe_load(result, aliases: true)
    assert_equal "プロフィール", result_data["ja"]["navigation"]["profile"]
    assert_equal "さようなら", result_data["ja"]["messages"]["goodbye"]
  end

  def test_formatting_preservation_issue
    # Current implementation using to_yaml
    original_data = YAML.safe_load(@target_content_with_formatting, aliases: true)
    
    # Add a new key
    original_data["ja"]["navigation"]["profile"] = "プロフィール"
    
    # Convert back to YAML (this is what the current implementation does)
    result_with_to_yaml = original_data.to_yaml
    
    puts "Original content:"
    puts @target_content_with_formatting
    puts "\nResult with to_yaml (loses formatting):"
    puts result_with_to_yaml
    
    # Demonstrate the issues:
    # 1. Lost anchors (&ja_locale, &shared_section)
    refute_includes result_with_to_yaml, "&ja_locale"
    refute_includes result_with_to_yaml, "&shared_section"
    
    # 2. Lost aliases (*shared_section)
    refute_includes result_with_to_yaml, "*shared_section"
    
    # 3. Lost comments
    refute_includes result_with_to_yaml, "# This is a comment"
    
    # 4. Lost specific quote styles (single quotes become double quotes or no quotes)
    refute_includes result_with_to_yaml, "'ログイン'"
    
    # This test demonstrates what we need to fix
    puts "\n❌ Current implementation loses:"
    puts "- Anchors (&ja_locale, &shared_section)"
    puts "- Aliases (*shared_section)"  
    puts "- Comments"
    puts "- Specific quote styles"
  end
end