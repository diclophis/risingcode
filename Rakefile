require 'rubygems'
require 'rake'
require '/var/www/risingcode/risingcode'
require '/var/www/risingcode/boot'
 
desc "Default Task"
task :default => [ :migrate ]

desc "Migrate"
task :migrate do
  puts "migrating..."
  RisingCode::Models.create_schema
end

desc "Twit"
task :twit do
  puts "twitting"
  searched = Referrer.parse("http://www.google.com/search?hl=en&rlz=1G1GGLQ_ENUS281&q=land+of+the+rising+code&btnG=Search")
  if searched then
    status = "Somebody found '#{searched[1]}' at http://risingcode.com"
    Twitter.update(status)
  end
end

=begin
if __FILE__ == $0 then
  daemon = ARGV.shift.intern if ARGV.length > 0
  drb = "druby://:2527"
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
