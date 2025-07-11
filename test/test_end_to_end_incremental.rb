# frozen_string_literal: true

require "test_helper"

class TestEndToEndIncremental < Minitest::Test
  def setup
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
    @target_file = File.join(@temp_dir, "source.ja.yml")
    
    File.write(@source_file, @source_content)
    File.write(@target_file, @target_content)
  end
  
  def teardown
    FileUtils.rm_rf(@temp_dir)
  end
  
  def test_end_to_end_incremental_translation
    # Mock the translator
    translator = Minitest::Mock.new
    
    # Mock translations for each key
    translator.expect(:translate_yaml_content, "ja:\n  navigation:\n    profile: プロフィール\n", [String, "en", "ja"])
    translator.expect(:translate_yaml_content, "ja:\n  forms:\n    signup:\n      title: サインアップ\n", [String, "en", "ja"])
    translator.expect(:translate_yaml_content, "ja:\n  forms:\n    signup:\n      submit: アカウント作成\n", [String, "en", "ja"])
    translator.expect(:translate_yaml_content, "ja:\n  messages:\n    goodbye: さようなら\n", [String, "en", "ja"])
    translator.expect(:translate_yaml_content, "ja:\n  shared:\n    buttons:\n      cancel: キャンセル\n", [String, "en", "ja"])
    
    cli = Honyaku::CLI.new
    result = cli.send(:process_incremental_translation, @source_file, @target_file, translator, "en", "ja")
    
    puts "Result from incremental translation:"
    puts result.inspect
    
    # Parse the result to verify structure
    result_data = YAML.safe_load(result)
    
    # Check that new keys were inserted in the correct nested location
    assert_equal "プロフィール", result_data["ja"]["navigation"]["profile"]
    assert_equal "サインアップ", result_data["ja"]["forms"]["signup"]["title"]
    assert_equal "アカウント作成", result_data["ja"]["forms"]["signup"]["submit"]
    assert_equal "さようなら", result_data["ja"]["messages"]["goodbye"]
    assert_equal "キャンセル", result_data["ja"]["shared"]["buttons"]["cancel"]
    
    # Check that existing keys are preserved
    assert_equal "ダッシュボード", result_data["ja"]["navigation"]["dashboard"]
    assert_equal "設定", result_data["ja"]["navigation"]["settings"]
    assert_equal "ログイン", result_data["ja"]["forms"]["login"]["title"]
    assert_equal "サインイン", result_data["ja"]["forms"]["login"]["submit"]
    assert_equal "ようこそ", result_data["ja"]["messages"]["welcome"]
    assert_equal "保存", result_data["ja"]["shared"]["buttons"]["save"]
    
    puts "Final merged YAML:"
    puts result
    
    translator.verify
  end
end