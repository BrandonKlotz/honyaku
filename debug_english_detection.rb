#!/usr/bin/env ruby

def is_english_text?(text)
  # More conservative English detection
  return false if text.length < 2  # Too short to determine
  
  # Count different character types using proper Unicode ranges
  ascii_letters = text.scan(/[A-Za-z]/).length
  # Use proper Unicode ranges for Japanese characters
  hiragana = text.scan(/[\u3040-\u309F]/).length      # Hiragana
  katakana = text.scan(/[\u30A0-\u30FF]/).length      # Katakana  
  kanji = text.scan(/[\u4E00-\u9FAF]/).length          # CJK Unified Ideographs (Kanji)
  japanese_chars = hiragana + katakana + kanji
  
  total_letters = ascii_letters + japanese_chars
  
  puts "Text: '#{text}'"
  puts "  ASCII letters: #{ascii_letters}"
  puts "  Japanese chars: #{japanese_chars} (hiragana: #{hiragana}, katakana: #{katakana}, kanji: #{kanji})"
  puts "  Total letters: #{total_letters}"
  
  # Only consider it English if:
  # 1. It has ASCII letters
  # 2. It has no Japanese characters OR ASCII letters significantly outnumber Japanese
  # 3. It's not just numbers/symbols
  return false if ascii_letters == 0
  return false if total_letters == 0
  
  # If there are Japanese characters, English must be dominant
  if japanese_chars > 0
    result = ascii_letters > japanese_chars * 2  # English must be 2:1 ratio
    puts "  Has Japanese chars, checking ratio: #{ascii_letters} > #{japanese_chars * 2} = #{result}"
    return result
  end
  
  # No Japanese characters, check if it looks like English words
  result = ascii_letters > text.length * 0.3  # At least 30% letters
  puts "  No Japanese chars, checking letter ratio: #{ascii_letters} > #{text.length * 0.3} = #{result}"
  return result
end

# Test cases
test_cases = [
  "Hello World こんにちは",
  "こんにちは さようなら Hello"
]

test_cases.each do |text|
  result = is_english_text?(text)
  puts "Result: #{result}\n\n"
end