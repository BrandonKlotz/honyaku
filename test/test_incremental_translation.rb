# frozen_string_literal: true

require "test_helper"

class TestIncrementalTranslation < Minitest::Test
  def setup
    @cli = Honyaku::CLI.new
    @temp_dir = Dir.mktmpdir
    
    # Create test source file with nested structure
    @source_content = <<~YAML
      en:
        navigation:
          dashboard: Dashboard
          settings: Settings
          profile: Profile
        forms:
          login:
            title: Login
            submit: Sign In
          signup:
            title: Sign Up
            submit: Create Account
        messages:
          welcome: Welcome
          goodbye: Goodbye
        shared:
          buttons:
            save: Save
            cancel: Cancel
    YAML
    
    # Create test target file missing some keys
    @target_content = <<~YAML
      ja:
        navigation:
          dashboard: ダッシュボード
          settings: 設定
        forms:
          login:
            title: ログイン
            submit: サインイン
        messages:
          welcome: ようこそ
        shared:
          buttons:
            save: 保存
    YAML
    
    @source_file = File.join(@temp_dir, "source.en.yml")
    @target_file = File.join(@temp_dir, "target.ja.yml")
    
    File.write(@source_file, @source_content)
    File.write(@target_file, @target_content)
  end
  
  def teardown
    FileUtils.rm_rf(@temp_dir)
  end
  
  def test_find_new_keys_with_nested_structure
    source_data = YAML.safe_load(@source_content, aliases: true)
    target_data = YAML.safe_load(@target_content, aliases: true)
    
    new_keys = @cli.send(:find_new_keys, source_data, target_data)
    
    expected_keys = [
      "en.navigation.profile",
      "en.forms.signup.title", 
      "en.forms.signup.submit",
      "en.messages.goodbye",
      "en.shared.buttons.cancel"
    ]
    
    assert_equal expected_keys.sort, new_keys.sort
  end
  
  def test_extract_key_values_for_nested_keys
    source_data = YAML.safe_load(@source_content, aliases: true)
    new_keys = ["en.navigation.profile", "en.forms.signup.title", "en.shared.buttons.cancel"]
    
    key_values = @cli.send(:extract_key_values, source_data, new_keys)
    
    expected_values = {
      "en.navigation.profile" => "Profile",
      "en.forms.signup.title" => "Sign Up", 
      "en.shared.buttons.cancel" => "Cancel"
    }
    
    assert_equal expected_values, key_values
  end
  
  def test_merge_keys_preserving_structure
    # Test the merge_keys_preserving_structure method
    translated_keys = {
      "en.navigation.profile" => "プロフィール",
      "en.forms.signup.title" => "サインアップ",
      "en.forms.signup.submit" => "アカウント作成",
      "en.messages.goodbye" => "さようなら",
      "en.shared.buttons.cancel" => "キャンセル"
    }
    
    result = @cli.send(:merge_keys_preserving_structure, @target_content, translated_keys, "ja")
    
    # Parse the result to verify structure
    result_data = YAML.safe_load(result)
    
    # Check that keys were inserted in the correct nested location
    assert_equal "プロフィール", result_data["ja"]["navigation"]["profile"]
    assert_equal "サインアップ", result_data["ja"]["forms"]["signup"]["title"]
    assert_equal "アカウント作成", result_data["ja"]["forms"]["signup"]["submit"]
    assert_equal "さようなら", result_data["ja"]["messages"]["goodbye"]
    assert_equal "キャンセル", result_data["ja"]["shared"]["buttons"]["cancel"]
    
    # Check that existing keys are preserved
    assert_equal "ダッシュボード", result_data["ja"]["navigation"]["dashboard"]
    assert_equal "ログイン", result_data["ja"]["forms"]["login"]["title"]
    assert_equal "保存", result_data["ja"]["shared"]["buttons"]["save"]
    
    puts "Merged YAML structure:"
    puts result
  end
end