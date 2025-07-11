# frozen_string_literal: true

require "test_helper"

class TestCopyReplaceFormatting < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
  end
  
  def teardown
    FileUtils.rm_rf(@temp_dir)
  end
  
  def test_perfect_formatting_preservation_with_anchors_and_aliases
    # English source file with complex formatting
    source_content = <<~YAML
      en: &en_locale
        navigation:
          dashboard: "Dashboard"
          settings: 'Settings'
          profile: Profile
          # Important navigation comment
        shared: &shared_buttons
          save: "Save"
          cancel: Cancel
          delete: 'Delete'
        forms:
          login:
            title: "Login Form"
            buttons: *shared_buttons
          signup:
            title: Sign Up Form
            submit: Create Account
        # End of forms section
        messages:
          welcome: "Welcome!"
          error: 'Error occurred'
          success: Success
    YAML
    
    # Existing Japanese translations (partial)
    target_content = <<~YAML
      ja:
        navigation:
          dashboard: "ダッシュボード"
          settings: '設定'
        shared:
          save: "保存"
          cancel: キャンセル
        forms:
          login:
            title: "ログインフォーム"
        messages:
          welcome: "ようこそ！"
          error: 'エラーが発生しました'
    YAML
    
    source_file = File.join(@temp_dir, "test.en.yml")
    target_file = File.join(@temp_dir, "test.ja.yml")
    
    File.write(source_file, source_content)
    File.write(target_file, target_content)
    
    # Mock translator for new keys
    translator = Minitest::Mock.new
    translator.expect(:translate_yaml_content, "ja:\n  navigation:\n    profile: プロフィール\n", [String, "en", "ja"])
    translator.expect(:translate_yaml_content, "ja:\n  shared:\n    delete: 削除\n", [String, "en", "ja"])
    translator.expect(:translate_yaml_content, "ja:\n  forms:\n    signup:\n      title: サインアップフォーム\n", [String, "en", "ja"])
    translator.expect(:translate_yaml_content, "ja:\n  forms:\n    signup:\n      submit: アカウント作成\n", [String, "en", "ja"])
    translator.expect(:translate_yaml_content, "ja:\n  messages:\n    success: 成功\n", [String, "en", "ja"])
    
    cli = Honyaku::CLI.new
    result = cli.send(:process_incremental_translation, source_file, target_file, translator, "en", "ja")
    
    puts "Original English source:"
    puts source_content
    puts "\nExisting Japanese target:"
    puts target_content
    puts "\nFinal result with perfect formatting preservation:"
    puts result
    
    # Verify perfect formatting preservation
    assert_includes result, "ja: &en_locale", "Should preserve anchor exactly"
    assert_includes result, "&shared_buttons", "Should preserve shared_buttons anchor"
    assert_includes result, "*shared_buttons", "Should preserve alias reference"
    assert_includes result, "# Important navigation comment", "Should preserve comments"
    assert_includes result, "# End of forms section", "Should preserve section comments"
    
    # Verify quote style preservation
    assert_includes result, '"ダッシュボード"', "Should preserve double quotes"
    assert_includes result, "'設定'", "Should preserve single quotes"
    assert_includes result, 'profile: プロフィール', "Should preserve unquoted style"
    assert_includes result, '"保存"', "Should preserve existing double quotes"
    assert_includes result, "'削除'", "Should preserve single quote style for new translation"
    
    # Verify existing translations are preserved
    assert_includes result, "ダッシュボード", "Should keep existing dashboard translation"
    assert_includes result, "設定", "Should keep existing settings translation"
    assert_includes result, "保存", "Should keep existing save translation"
    assert_includes result, "キャンセル", "Should keep existing cancel translation"
    assert_includes result, "ログインフォーム", "Should keep existing login title"
    assert_includes result, "ようこそ！", "Should keep existing welcome translation"
    assert_includes result, "エラーが発生しました", "Should keep existing error translation"
    
    # Verify new translations were added
    assert_includes result, "プロフィール", "Should add profile translation"
    assert_includes result, "削除", "Should add delete translation"
    assert_includes result, "サインアップフォーム", "Should add signup title translation"
    assert_includes result, "アカウント作成", "Should add signup submit translation"
    assert_includes result, "成功", "Should add success translation"
    
    # Verify YAML structure is valid and parseable
    result_data = YAML.safe_load(result, aliases: true)
    assert_equal "ダッシュボード", result_data["ja"]["navigation"]["dashboard"]
    assert_equal "プロフィール", result_data["ja"]["navigation"]["profile"]
    assert_equal "保存", result_data["ja"]["shared"]["save"]
    assert_equal "削除", result_data["ja"]["shared"]["delete"]
    assert_equal "ログインフォーム", result_data["ja"]["forms"]["login"]["title"]
    assert_equal "サインアップフォーム", result_data["ja"]["forms"]["signup"]["title"]
    assert_equal "成功", result_data["ja"]["messages"]["success"]
    
    # Verify alias functionality still works
    assert_equal result_data["ja"]["shared"], result_data["ja"]["forms"]["login"]["buttons"]
    
    translator.verify
  end
end