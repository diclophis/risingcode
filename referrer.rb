class Referrer
  SEARCH_PARAMS = {
    'AltaVista' => 'q',
    'Ask' => 'q',
    'Google' => 'q',
    'Live' => 'q',
    'Lycos' => 'query',
    'MSN' => 'q',
    'Yahoo' => 'p',
  }

  def self.parse (url)
    begin
      uri = URI.parse(url)
      query = CGI.parse(uri.query)
      SEARCH_PARAMS.each { |host, parameter|
        if uri.host.include?(host.downcase) then
          return [host, query[parameter]]
        end
      }
    rescue
    end
    return nil
  end
end
