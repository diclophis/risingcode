module OEmbed
  class RisingCodeCache
    @cache_enabled = true
    class << self
      attr_writer :expiry, :host
      def enabled?
        @cache_enabled
      end
      def enable!
        #@cache ||= MemCache.new(host, :namespace => "openuri")
        @cache_enabled = false
      end
      def disable!
        @cache_enabled = false
      end
      def disabled?
        !@cache_enabled
      end
      def xget(key)
        @cache.get(key)
      end
      def xset(key, value)
        @cache.set(key, value, expiry)
      end
      def get(key)
        value = @cache.get(key)
        if value.is_a?(Exception) then
Camping::Models::Base.logger.debug("NOT GONNA GET IT 999")
#Camping::Models::Base.logger.debug(value.backtrace.join("\n"))
          nil
        else
          if value then
Camping::Models::Base.logger.debug("#{key} cached! 999") if value.nil?
          else
Camping::Models::Base.logger.debug("#{key} NOT cached! 999") if value.nil?
          end
          value
        end
      end
      
      def set(key, value)
        if value.is_a?(Exception) then
Camping::Models::Base.logger.debug("NOT GONNA PUT IT 999")
#Camping::Models::Base.logger.debug(value.backtrace.join("\n"))
        else
Camping::Models::Base.logger.debug("setting #{key} 999")
          @cache.set(key, value, expiry)
        end
      end
      def expiry
        @expiry ||= 60 * 60 * 24 * 30
      end
      def alive?
        servers = @cache.instance_variable_get(:@servers) and servers.collect{|s| s.alive?}.include?(true)
      end
      def host
        @host ||= "localhost:11211"
      end
    end
  end
  class Provider
    attr_accessor :format, :name, :url, :urls, :endpoint

    def initialize(endpoint, format = :json)
      @endpoint = endpoint
      @urls = []
      @format = format
    end

    def <<(url)
      full, scheme, domain, path = *url.match(%r{([^:]*)://?([^/?]*)(.*)})
      domain = Regexp.escape(domain).gsub("\\*", "(.*?)").gsub("(.*?)\\.", "([^\\.]+\\.)?")
      path = Regexp.escape(path).gsub("\\*", "(.*?)")
      @urls << Regexp.new("^#{Regexp.escape(scheme)}://#{domain}#{path}")
    end

    def build(url, options = {})
      raise OEmbed::NotFound, url unless include?(url)
      query = options.merge({:url => url})
      endpoint = @endpoint.clone

      if format_in_url?
        format = endpoint["{format}"] = (query[:format] || @format).to_s
        query.delete(:format)
      else
        format = query[:format] ||= @format
      end

      query_string = "?" + query.inject("") do |memo, (key, value)|
        value = URI.encode("#{value}")
        memo = URI.encode("#{memo}")
        "#{key}=#{value}&#{memo}"
      end.chop

      URI.parse(endpoint + query_string).instance_eval do
        @format = format; def format; @format; end
        self
      end
    end

    def raw(url, options = {})
      uri = build(url, options)
Camping::Models::Base.logger.debug("111")
      if RisingCodeCache.enabled? and RisingCodeCache::alive?
        begin
          response = RisingCodeCache::get("oembed" + url)
#Camping::Models::Base.logger.debug("got from from cache #{response.inspect}")
        rescue
          response = nil
        end
      end
Camping::Models::Base.logger.debug("222")
#Camping::Models::Base.logger.debug("from cache is exception #{response.is_a? Exception}")
      unless response
Camping::Models::Base.logger.debug("333")
        res = Net::HTTP.start(uri.host, uri.port) do |http|
          http.get(uri.request_uri)
        end
Camping::Models::Base.logger.debug("this is something funny 1 #{res.inspect}")
#Camping::Models::Base.logger.debug("from oohemb #{url}")
        case res
        #when Net::HTTPNotImplemented
        #  response = Exception.new
        #when Net::HTTPNotFound
        #  response = Exception.new
          when Net::HTTPOK
            response = res.body
        else
Camping::Models::Base.logger.debug("this is something funny 2 #{uri.request_uri} #{res.inspect}")

          response = Exception.new("something?")
        end
        RisingCodeCache::set("oembed" + url, response) if RisingCodeCache.alive?
      end
Camping::Models::Base.logger.debug("444")
#Camping::Models::Base.logger.debug("after is exception #{response.is_a? Exception}")
      if response.is_a? Exception then
Camping::Models::Base.logger.debug("response chung")
Camping::Models::Base.logger.debug("!!!!!!!!!!!!!!!!!#{response.inspect}")
        #Camping::Models::Base.logger.debug(response.backtrace.join("\n"))
        return response
      end
      StringIO.new(response)
    end

    def get(url, options = {})
      OEmbed::Response.create_for(raw(url, options.merge(:format => :json)), self)
    end

    def format_in_url?
      @endpoint.include?("{format}")
    end

    def include?(url)
      @urls.empty? || !!@urls.detect{ |u| u =~ url }
    end
  end
end
