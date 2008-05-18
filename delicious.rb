require 'net/https'
require 'rexml/document'

module Delicious
  class Bookmarks
    @@bookmarks_filename = nil
    @@cache = Hash.new
    @@cache_lifetime = 24 * 60 * 60
    @@cache_created = Time.now
    @@force_expire_cache = false

    def Bookmarks.all (start = 0, limit = 100)
      cache_key = "#{start}:#{limit}"
      if @@cache[cache_key].nil? or @@force_expire_cache or ((@@cache_created + @@cache_lifetime) < Time.now) then
        dates = ::ActiveSupport::OrderedHash.new
        unless @@bookmarks_filename.nil?
          xml = File.open(@@bookmarks_filename)
          doc = REXML::Document.new(xml)
          doc.root.elements.to_a.slice(start,limit).each { |element|
            date = Time.parse(element.attributes["time"]).strftime("%Y-%m-%d")
            dates[date] = Array.new if dates[date].nil?
            text = element.attributes["description"]
            length = 60 
            truncate_string = "..."
            l = length - truncate_string.chars.length
            excerpt = text.chars.length > length ? text.chars[0...l] + truncate_string : text
            element.attributes["excerpt"] = excerpt 
            dates[date] << element.attributes
          }
        end
        @@cache[cache_key] = dates
        @@cache_created = Time.now
      end
      return @@cache[cache_key]
    end
  end
end
