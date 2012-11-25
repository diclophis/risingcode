#JonBardin

module RisingCode
  module Base
    def r404(p=env.PATH)
      @status = 404
      "Lost?"
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
