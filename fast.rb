#JonBardin
module Fast
  def self.fetch(url, recursed = false, &block)
    cache = true
#Camping::Models::Base.logger.debug("\n\n\n\n\n\n")
#Camping::Models::Base.logger.debug(url.inspect)
#Camping::Models::Base.logger.debug(recursed.inspect)
    uri = URI.parse(url)
    if Cache.enabled? and Cache::alive?
      begin
        response = Cache::get("fast" + url)
Camping::Models::Base.logger.debug("cached #{url}")
      rescue
        response = nil
      end
    end
    unless response
      res = Net::HTTP.start(uri.host, uri.port) do |http|
        http.get(uri.request_uri)
      end
Camping::Models::Base.logger.debug("fetched #{url}")
#Camping::Models::Base.logger.debug("fetched #{res.inspect}")
      case res
        when Net::HTTPRedirection
          raise "Too Much Recursion" if recursed
          response = self.fetch(res['location'], true)
#Camping::Models::Base.logger.debug("got from recurse" + response.inspect)
          cache = false
        when Net::HTTPNotImplemented
          response = nil
        when Net::HTTPNotFound
          response = nil
        when Net::HTTPOK
        begin
          reader = Zlib::GzipReader.new(StringIO.new(res.body))
          body = reader.readlines.join("\n")
        rescue
          body = res.body
        end

          if recursed then
#Camping::Models::Base.logger.debug("some recursion")
#Camping::Models::Base.logger.debug("returninga" + body.inspect)
            return body
          else
            response = body
          end
      else
        response = nil
      end
      if cache then
        Cache::set("fast" + url, response) if (Cache.alive?)
      else
#Camping::Models::Base.logger.debug("not caching")
      end
    end
#Camping::Models::Base.logger.debug("end")
#Camping::Models::Base.logger.debug("returningb" + response.slice(0, 10))
    return response
  end
  
  class Cache
    # Cache is not enabled by default
    @cache_enabled = false
    
    class << self
      attr_writer :expiry, :host
      
      # Is the cache enabled?
      def enabled?
        @cache_enabled
      end
      
      # Enable caching
      def enable!
        @cache ||= MemCache.new(host, :namespace => "openuri")
        @cache_enabled = true
      end
      
      # Disable caching - all queries will be run directly 
      # using the standard OpenURI `open` method.
      def disable!
        @cache_enabled = false
      end

      def disabled?
        !@cache_enabled
      end
      
      def get(key)
        @cache.get(key)
      end
      
      def set(key, value)
        @cache.set(key, value, expiry)
      end
            
      # How long your caches will be kept for (in seconds)
      def expiry
        @expiry ||= 60 * 60 * 24 * 30
        #@expiry ||= 0
      end
      
      def alive?
        servers = @cache.instance_variable_get(:@servers) and servers.collect{|s| s.alive?}.include?(true)
      end
      
      def host
        @host ||= "localhost:11211"
      end
    end
  end
end
