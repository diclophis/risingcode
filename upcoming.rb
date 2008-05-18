#JonBardin

require 'rubygems'
require 'upcoming'

module Upcoming
#  class Auth
#    API_KEY = "40bcdd259e"
#  end

  class Event
    @@cache = Hash.new
    @@cache_lifetime = 2 * 60 * 60
    @@cache_created = Hash.new
    @@force_expire_cache = false

    attr_accessor :excerpt, :venue_address, :venue_name, :venue_url, :venue_city, :venue_state_name, :url

    def initialize(attrs_hash)
      @id             = attrs_hash[:id]
      @name           = attrs_hash[:name]
      @description    = attrs_hash[:description]
      @start_date     = attrs_hash[:start_date]
      @end_date       = attrs_hash[:end_date]
      @start_time     = attrs_hash[:start_time]
      @end_time       = attrs_hash[:end_time]
      @date_posted    = attrs_hash[:date_posted]
      @personal       = attrs_hash[:personal]
      @self_promotion = attrs_hash[:self_promotion]
      @lat            = attrs_hash[:lat]
      @lng            = attrs_hash[:lng]
      @gc_precision   = attrs_hash[:gc_precision]
      @gc_ambiguous   = attrs_hash[:gc_ambiguous]
      @user_id        = attrs_hash[:user_id]
      @category_id    = attrs_hash[:category_id]
      @venue_id       = attrs_hash[:venue_id]
      @metro_id       = attrs_hash[:metro_id]
      @state_id       = attrs_hash[:state_id]
      @country_id     = attrs_hash[:country_id]
      @venue_url     = attrs_hash[:venue_url]
      @venue_name     = attrs_hash[:venue_name]
      @venue_address     = attrs_hash[:venue_address]
      @venue_city     = attrs_hash[:venue_city]
      @venue_state_name     = attrs_hash[:venue_state_name]
      @url     = attrs_hash[:url]
    end

    def self.create_from_node(node)
      attrs = {}
      
      attrs[:id] = node.attribute('id').value
      attrs[:name] = node.attribute('name').value
      attrs[:description] = node.attribute('description').value
      attrs[:start_date] = node.attribute('start_date').value
      attrs[:end_date] = node.attribute('end_date').value
      attrs[:start_time] = node.attribute('start_time').value
      attrs[:end_time] = node.attribute('end_time').value
      attrs[:date_posted] = node.attribute('date_posted').value
      attrs[:personal] = node.attribute('personal').value
      attrs[:self_promotion] = node.attribute('selfpromotion').value
      attrs[:lat] = node.attribute('latitude').value
      attrs[:lng] = node.attribute('longitude').value
      attrs[:gc_precision] = node.attribute('geocoding_precision').value
      attrs[:gc_ambiguous] = node.attribute('geocoding_ambiguous').value
      attrs[:user_id] = node.attribute('user_id').value
      attrs[:category_id] = node.attribute('category_id').value
      attrs[:venue_id] = node.attribute('venue_id').value
      attrs[:metro_id] = node.attribute('metro_id').value
      attrs[:state_id] = node.attribute('venue_state_id').value
      attrs[:country_id] = node.attribute('venue_country_id').value

      attrs[:venue_url] = node.attribute('venue_url').value unless node.attribute('venue_url').nil?
      attrs[:venue_name] = node.attribute('venue_name').value unless node.attribute('venue_name').nil?
      attrs[:venue_address] = node.attribute('venue_address').value unless node.attribute('venue_address').nil?
      attrs[:venue_city] = node.attribute('venue_city').value unless node.attribute('venue_city').nil?
      attrs[:venue_state_name] = node.attribute('venue_state_name').value unless node.attribute('venue_state_name').nil?
      attrs[:url] = node.attribute('url').value unless node.attribute('url').nil?
      
      Event.new(attrs)
    end

    def self.get_info (event_id)
      cache_key = "#{event_id}"
      if @@cache[cache_key].nil? or @@force_expire_cache or ((@@cache_created[cache_key] + @@cache_lifetime) < Time.now) then
        params = {:method => "event.getInfo", :event_id => event_id}
        req = Upcoming::Request.new
        url = req.get_url(params)
        #Camping::Models::Base.logger.debug("#{url}")
        resp = req.send(params)
        doc = Document.new(resp.body)
        event = nil
        XPath.each(doc, '//event') { |el|
          event = Event.create_from_node(el)
          break
        }
        @@cache[cache_key] = event
        @@cache_created[cache_key] = Time.now
      end
      return @@cache[cache_key]
    end
  end

  class Events
    @@cache = Hash.new
    @@cache_lifetime = 8 * 60 * 60
    @@cache_created = Time.now
    @@force_expire_cache = false

    def Events.all (start = 0, limit = 1000)
      cache_key = "#{start}:#{limit}"
      if @@cache[cache_key].nil? or @@force_expire_cache or ((@@cache_created + @@cache_lifetime) < Time.now) then
        three_days_from_now = Time.now + (1 * 24 * 60 * 60)
        params = {
          :location => "San Francisco Bay Area, California",
          :max_date => three_days_from_now.strftime("%Y-%m-%d"), 
          :sort => "start-date-asc"
        }
        request = Upcoming::Request.new
        url = request.get_url(params)
        #Camping::Models::Base.logger.debug("#{url}&method=event.search")
        events = Upcoming::Event.search(params)
        dates = Hash.new
        events.each { |event|
          dates[event.start_date] = Array.new if dates[event.start_date].nil?
          text = (event.name)
          length = 1000 
          truncate_string = "..."
          l = length - truncate_string.chars.length
          event.excerpt = CGI.escapeHTML(text.chars.length > length ? text.chars[0...l] + truncate_string : text).gsub("/", "&#047;")
          dates[event.start_date] << event
        }
        @@cache[cache_key] = dates
        @@cache_created = Time.now
      end
      return @@cache[cache_key]
    end
  end
end
