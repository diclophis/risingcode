#JonBardin
#
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
      h1((p + " not found"))
    end)
  end
end
