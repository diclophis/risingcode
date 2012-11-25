require 'rubygems'
require 'rake'
require './risingcode.rb'
require './boot'
 
desc "Default Task"
task :default => [ :migrate ]

desc "Migrate"
task :migrate do
  puts "migrating..."
  RisingCode::Models.create_schema
end

desc "documentation server"
task :document do
  #DocumentationServer.daemon(["stop", "-t"])
  #DocumentationServer.daemon(["zap", "-t"])
  DocumentationServer.daemon(["start", "-f"])
end

desc "grab bookmarks"
task :bookmarks do
  cmd = ("curl --user #{Delicious::Bookmarks::USER}:#{Delicious::Bookmarks::PASS} -o /tmp/bookmarks.xml -O \"https://api.del.icio.us/v1/posts/all\"")
  `#{cmd}`
end
