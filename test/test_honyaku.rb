# frozen_string_literal: true

require_relative "test_helper"

class TestHonyaku < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Honyaku::VERSION
  end

  def test_keep_invalid_flag_preserves_file
    # Create a temporary directory for our test files
    Dir.mktmpdir do |dir|
      # Create a source file with valid YAML
      source_file = File.join(dir, "en.yml")
      File.write(source_file, "en:\n  hello: Hello")

      # Create a target file with invalid YAML
      target_file = File.join(dir, "ja.yml")
      File.write(target_file, "ja:\n  hello: こんにちは\n  invalid: [unclosed array")

      # Mock the translator to simulate YAML validation failure
      translator = Minitest::Mock.new
      translator.expect :translate_hash, "ja:\n  hello: こんにちは\n  invalid: [unclosed array", [String, String, String]
      translator.expect :fix_yaml, nil do |file|
        raise "needs retranslation" # Simulate YAML validation failure
      end

      # Create CLI instance with keep_invalid flag
      cli = Honyaku::CLI.new
      cli.options = { keep_invalid: true }

      # Run the translation
      cli.send(:process_file, source_file, translator, "en", "ja")

      # Verify the file still exists despite the error
      assert File.exist?(target_file), "File should be preserved when keep_invalid is true"
      assert_equal "ja:\n  hello: こんにちは\n  invalid: [unclosed array", File.read(target_file)
    end
  end
end
