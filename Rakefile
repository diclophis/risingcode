require 'rubygems'
require 'rake'
require '/home/ubuntu/risingcode/risingcode'
require '/home/ubuntu/risingcode/boot'
 
desc "Default Task"
task :default => [ :migrate ]

desc "Migrate"
task :migrate do
  puts "migrating..."
  require '/var/www/risingcode/boot'
  RisingCode::Models.create_schema
end

desc "documentation server"
task :document do
  DocumentationServer.daemon(["stop", "-t"])
  #DocumentationServer.daemon(["zap", "-t"])
  #DocumentationServer.daemon(["start", "-f"])
end

desc "grab bookmarks"
task :bookmarks do
  cmd = ("curl --user #{Delicious::Bookmarks::USER}:#{Delicious::Bookmarks::PASS} -o /tmp/bookmarks.xml -O \"https://api.del.icio.us/v1/posts/all\"")
  `#{cmd}`
end

desc "flush cache"
task :flush do
  MemCache.new("localhost:11211", :namespace => "openuri").flush_all
end


=begin
if __FILE__ == $0 then
  daemon = ARGV.shift.intern if ARGV.length > 0
  case daemon
    when :documentation_client
      DRb.start_service
      documentation_server = DRbObject.new(nil, drb)
      documentation_server.controllers.each { |controller|
        puts documentation_server.source_for(controller)
      }

    when :documentation_server
      DocumentationServer.daemon("risingcode_documentation_server", '/var/www/risingcode.com/boot', drb)


    when :email_server
      EmailServer.daemon("risingcode_email_server", '/var/www/risingcode.com/boot', 2525)

    when :runner
      require "boot"
      wang = RedCloth.highlight("puts :wang if :chung")
      Camping::Models::Base.logger.debug(wang)
      drb = "druby://:2527"
      DRb.start_service
      @@documentation_server = DRbObject.new(nil, drb)
      wang = @@documentation_server.source_for(RisingCode::Controllers::Login)
      Camping::Models::Base.logger.debug(wang)
  else
    puts "wtf"
  end
else
  #drb = "druby://:2527"
  #DRb.start_service
  #@@documentation_server = DRbObject.new(nil, drb)
  #require ENV['COMP_ROOT'] + "/boot"
end
=end
