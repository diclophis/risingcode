#

#app = Rack::Builder.new do
#  use Rack::ShowExceptions
#
#	use(Rack::Static, urls: ["/index.html", "/favicon.ico"], root: "public")
#
#  map "/" do
#    run IndexLayer
#  end
#
#  map "/index.json" do
#    run IndexLayer
#  end
#
#  map "/begin" do
#    run BeginUpload
#  end
#
#  map "/end" do
#    run EndUpload
#  end
#
#  map "/upload" do
#    run StorageLayer
#  end
#
#  map "/download" do
#    run StorageLayer
#  end
#
#  map "/delete" do
#    run StorageLayer
#  end
#end
#
#run app

require './risingcode'
require './boot'

RisingCode::Models::Tagging.connection

use Rack::Static, :urls => ["/favicon.ico", "/images", "/robots.txt", "/stylesheets", "/javascripts"], :root => 'public'

run RisingCode
