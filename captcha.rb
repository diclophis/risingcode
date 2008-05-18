
  class Captcha < R("/captcha")
    def self.description
      "wang chung"
    end
    def get
      # Generate a new captcha with the following before rendering this view
      if not @state.captcha then
        chars = ("B".."D").to_a + ("F".."H").to_a + ("J".."N").to_a + ("P".."T").to_a + ("V".."Z").to_a
        captcha = ""
        1.upto(6) { |i| captcha << chars[rand(chars.size-1)] }
        @state.captcha = captcha
      end

      # Retrieve the background color
      bgcolor = @input.bc
      # If the background color wasn't specified, use black
      if bgcolor == nil
        bgcolor = 'white'
      end
      # If this is not a CSS2 color, then it must be a hex value.
      if bgcolor.match('[g-zG-Z]')
      else
        bgcolor = "#" + bgcolor
      end
    
      # Retrieve the color
      fgcolor = @input.c
      # If the foreground color wasn't specified, use white
      if fgcolor == nil
        fgcolor = 'black'
      end
      # If this is not a CSS2 color, then it must be a hex value.
      if fgcolor.match('[g-zG-Z]')
      else
        fgcolor = "#" + fgcolor
      end

      # Create a new image
      img = Magick::Image.new(100,50) {
        self.background_color = bgcolor
      }
      
      # Create a new drawing object
      gc = Magick::Draw.new

      # Draw a bunch of random horizontal and vertical lines
      gc.fill(fgcolor)
      gc.fill_opacity(0.2)
      5.times {
        x = rand(100)
        gc.rectangle(x,0,x,50)
      }
      5.times {
        y = rand(50)
        gc.rectangle(0,y,100,y)
      }
      gc.fill_opacity(0.5)
      5.times {
        x = rand(100)
        gc.rectangle(x,0,x,50)
      }
      5.times {
        y = rand(50)
        gc.rectangle(0,y,100,y)
      }
      # Dump the drawing to the image
      gc.draw(img)

      # Apply a random wave effect
      img = img.wave(rand(5)+1,rand(5)+1)
      img = img.resize(100,50)
      
      # Create a new drawing object for the text
      text = Magick::Draw.new
      
      text.fill(fgcolor)
      #text.font = "#{RAILS_ROOT}/lib/fonts/Vera.ttf"
      # Adjust this to your implementation
      text.pointsize(18)
      text.font_style(Magick::NormalStyle)
      text.font_weight(Magick::BoldWeight)
      text.text_anchor(Magick::CenterAlign)
      text.text_antialias(true)
      
      # Write the text to the image
      text.text(50,30,@state.captcha)
      text.draw(img)
      
      # Add noise to the image
      img = img.add_noise(Magick::ImpulseNoise)

      # Adjust the quality to your liking
      blob = img.to_blob() {
        self.format = 'JPEG'
        self.quality = 30
      }
      @headers['Content-Type'] = "image/jpeg"
      @headers['Content-Disposition'] = "inline"
      blob
    end
