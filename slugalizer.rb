# Slugalizer
# http://github.com/henrik/slugalizer

class String
  def normalize(normalization_form=nil)
    self
  end
end

class Integer
  def ordinalize
    if (10...20) === self
      "#{self}th"
    else
      g = %w{ th st nd rd th th th th th th }
      a = self.to_s
      c=a[-1..-1].to_i
      a + g[c]
    end
  end
end

def returning(value)
  yield(value)
  value
end

module Slugalizer
  extend self
  SEPARATORS = %w[- _ +]
  
  def slugalize(text, separator = "-")
    unless SEPARATORS.include?(separator)
      raise "Word separator must be one of #{SEPARATORS}"
    end
    re_separator = Regexp.escape(separator)
    result = text.to_s.normalize
    result.gsub!(/[^\x00-\x7F]+/, '')                      # Remove non-ASCII (e.g. diacritics).
    result.gsub!(/[^a-z0-9\-_\+]+/i, separator)            # Turn non-slug chars into the separator.
    result.gsub!(/#{re_separator}{2,}/, separator)         # No more than one of the separator in a row.
    result.gsub!(/^#{re_separator}|#{re_separator}$/, '')  # Remove leading/trailing separator.
    result.downcase!
    result
  end
end
