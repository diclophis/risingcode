#

require './risingcode'
require './boot'

RisingCode::Models::Tagging.connection

DocumentationServer.daemon(ARGV)
