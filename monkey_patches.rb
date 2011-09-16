#JonBardin
#

=begin
class RisingCode::Controllers::ServerError
  def get(k, m, e)
    r(500, Mab.new do
      h1("Error")
      h2("#{k}.#{m}")
      h3("#{e.class} #{e.message}:")
      ul { e.backtrace.each { |bt| li(bt) } }
    end.to_s)
  end
end

class RisingCode::Controllers::NotFound
  def get(p)
    r(404, Mab.new do
      h1((p + " not found wtf"))
    end)
  end
end
=end
#require 'markaby'

module RisingCode
  module Base
    def r404(p=env.PATH)
      @status = 404
      "Lost?"
=begin
      return ::Markaby::Builder.new.xhtml_transitional {
        head {
          title {
            "wtf"
          }
        }
        body {
          h1 {
            "Lost?"
          }
        }
      }
=end
=begin

      #r(404, "#{p} not found")
      @status = 404
      @tags = RisingCode::Models::Tag.find_all_by_include_in_header(true)
      return ::Markaby::Builder.new.table {
        tr {
          td.lines {
            j.times { |i|
              text("#{i}\n")
              br
            }
          }
          td {
            text(h)
          }
        }
      }
      #h1 {
        "Lost?"
      #}
=end
    end
  end
end

class Array
  def at_center
    (length / 2).round
  end
  def center
    self[at_center]
  end
end
