# frozen_string_literal: true

require "test_helper"

class TestHonyaku < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Honyaku::VERSION
  end

  def test_it_does_something_useful
    # Test that we can create a CLI instance
    cli = Honyaku::CLI.new
    refute_nil cli
  end
end
