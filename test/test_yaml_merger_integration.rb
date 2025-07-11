# frozen_string_literal: true

require "test_helper"

class TestYamlMergerIntegration < Minitest::Test
  def setup
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
  end
  
  def test_merge_keys_with_nested_structure
    merger = Honyaku::YamlMerger.new
    
    new_keys = {
      "navigation.profile" => "プロフィール",
      "forms.signup.title" => "サインアップ",
      "forms.signup.submit" => "アカウント作成",
      "messages.goodbye" => "さようなら",
      "shared.buttons.cancel" => "キャンセル"
    }
    
    result = merger.merge_keys(@target_content, new_keys, "ja")
    
    puts "Result from merger:"
    puts result.inspect
    
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
    
    puts "Merged YAML content:"
    puts result
  end
end