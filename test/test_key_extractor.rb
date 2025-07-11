# frozen_string_literal: true

require_relative "test_helper"
require "tempfile"
require "honyaku/key_extractor"

class TestKeyExtractor < Minitest::Test
  def setup
    @source_content = <<~YAML
      en:
        greeting: "Hello"
        user:
          name: "Name"
          email: "Email"
        messages:
          welcome: "Welcome to our app"
          goodbye: "Goodbye"
        new_feature:
          title: "New Feature"
          description: "This is a new feature"
    YAML

    @target_content = <<~YAML
      ja:
        greeting: "こんにちは"
        user:
          name: "名前"
          email: "メール"
        messages:
          welcome: "アプリへようこそ"
          # goodbye is missing - this should be detected as needing translation
    YAML

    @source_file = create_temp_file(@source_content)
    @target_file = create_temp_file(@target_content)
  end

  def teardown
    [@source_file, @target_file].compact.each do |file|
      File.unlink(file) if File.exist?(file)
    end
  end

  def test_extract_new_keys_finds_missing_keys
    extractor = Honyaku::KeyExtractor.new(@source_file, @target_file)
    new_keys = extractor.extract_new_keys("en", "ja")

    expected_keys = {
      "messages.goodbye" => "Goodbye",
      "new_feature.title" => "New Feature", 
      "new_feature.description" => "This is a new feature"
    }

    assert_equal expected_keys, new_keys
  end

  def test_extract_new_keys_with_empty_target
    empty_target = create_temp_file("")
    extractor = Honyaku::KeyExtractor.new(@source_file, empty_target)
    new_keys = extractor.extract_new_keys("en", "ja")

    expected_keys = {
      "greeting" => "Hello",
      "user.name" => "Name",
      "user.email" => "Email", 
      "messages.welcome" => "Welcome to our app",
      "messages.goodbye" => "Goodbye",
      "new_feature.title" => "New Feature",
      "new_feature.description" => "This is a new feature"
    }

    assert_equal expected_keys, new_keys
    File.unlink(empty_target) if File.exist?(empty_target)
  end

  def test_extract_new_keys_with_nonexistent_target
    nonexistent_target = "/tmp/nonexistent_file.yml"
    extractor = Honyaku::KeyExtractor.new(@source_file, nonexistent_target)
    new_keys = extractor.extract_new_keys("en", "ja")

    expected_keys = {
      "greeting" => "Hello",
      "user.name" => "Name", 
      "user.email" => "Email",
      "messages.welcome" => "Welcome to our app",
      "messages.goodbye" => "Goodbye",
      "new_feature.title" => "New Feature",
      "new_feature.description" => "This is a new feature"
    }

    assert_equal expected_keys, new_keys
  end

  def test_extract_keys_needing_translation_finds_english_values
    mixed_target_content = <<~YAML
      ja:
        greeting: "こんにちは"
        user:
          name: "Name"  # This is still in English
          email: "メール"
        messages:
          welcome: "Welcome to our app"  # This is still in English
    YAML

    mixed_target = create_temp_file(mixed_target_content)
    extractor = Honyaku::KeyExtractor.new(@source_file, mixed_target)
    keys_needing_translation = extractor.extract_keys_needing_translation("en", "ja")

    expected_keys = {
      "user.name" => "Name",
      "messages.welcome" => "Welcome to our app"
    }

    assert_equal expected_keys, keys_needing_translation
    File.unlink(mixed_target) if File.exist?(mixed_target)
  end

  def test_extract_keys_needing_translation_with_no_english_values
    extractor = Honyaku::KeyExtractor.new(@source_file, @target_file)
    keys_needing_translation = extractor.extract_keys_needing_translation("en", "ja")

    # Since the target file is properly translated (no English values), should be empty
    assert_empty keys_needing_translation
  end

  def test_handles_yaml_with_aliases
    source_with_aliases = <<~YAML
      en:
        default: &default_message "Default message"
        greeting: *default_message
        user:
          welcome: "Welcome user"
    YAML

    target_with_aliases = <<~YAML
      ja:
        default: &default_message "デフォルトメッセージ"
        greeting: *default_message
        # user.welcome is missing
    YAML

    source_file = create_temp_file(source_with_aliases)
    target_file = create_temp_file(target_with_aliases)

    extractor = Honyaku::KeyExtractor.new(source_file, target_file)
    new_keys = extractor.extract_new_keys("en", "ja")

    expected_keys = {
      "user.welcome" => "Welcome user"
    }

    assert_equal expected_keys, new_keys

    [source_file, target_file].each do |file|
      File.unlink(file) if File.exist?(file)
    end
  end

  def test_handles_arrays_in_yaml
    source_with_arrays = <<~YAML
      en:
        items:
          - "First item"
          - "Second item"
        nested:
          list:
            - name: "Item 1"
              description: "First item description"
    YAML

    target_with_arrays = <<~YAML
      ja:
        items:
          - "最初のアイテム"
          # Second item is missing
    YAML

    source_file = create_temp_file(source_with_arrays)
    target_file = create_temp_file(target_with_arrays)

    extractor = Honyaku::KeyExtractor.new(source_file, target_file)
    new_keys = extractor.extract_new_keys("en", "ja")

    expected_keys = {
      "items[1]" => "Second item",
      "nested.list[0].name" => "Item 1",
      "nested.list[0].description" => "First item description"
    }

    assert_equal expected_keys, new_keys

    [source_file, target_file].each do |file|
      File.unlink(file) if File.exist?(file)
    end
  end

  private

  def create_temp_file(content)
    file = Tempfile.new(['test', '.yml'])
    file.write(content)
    file.close
    file.path
  end
end