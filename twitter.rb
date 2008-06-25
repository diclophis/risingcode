#JonBardin

class Twitter
  def self.update (status)
    #cmd = "curl -u '#{EMAIL}:#{PASSWORD}' -d status='#{status}' http://twitter.com/statuses/update.xml"
    #IO.popen(cmd)
    #open("http://#{EMAIL}:#{PASSWORD}@twitter.com/statuses/update.xml", :method => "post", :body => "status=#{status}")

    timeout(5) {
      Net::HTTP.post_form(URI.parse("http://#{EMAIL}:#{PASSWORD}@twitter.com/statuses/update.xml"), {'status' => status})
    }

  end
end
