#JonBardin

class Twitter
  def self.update (status)
    timeout(5) {
      Net::HTTP.post_form(URI.parse("http://#{EMAIL}:#{PASSWORD}@twitter.com/statuses/update.xml"), {'status' => status})
    }
  end
end
