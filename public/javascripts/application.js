/* JonBardin */

var delicious_glider = null;
var upcoming_glider = null;
var init_map = true;

var rules = {
  'body' : function (element) {
    delicious_glider = new Glider('delicious');
    upcoming_glider = new Glider('upcoming');
  },

 /* 
  '#older_bookmark_page' : function (element) {
    element.onclick = function () {
      //glider.next();
    }
    element.disabled = false;
  },

  '#newer_bookmark_page' : function (element) {
    element.onclick = function () {
      //glider.previous();
    }
  },
  */

  '#map' : function (element) {
      init_map = false;
      var mandelbrot_grid = new OpenLayers.Layer.WMS("Mandelbrot Grid", "http://risingcode.com/mandelbrot/generate.php");
      var map = new OpenLayers.Map("map", { controls: [] });
      map.addControl(new OpenLayers.Control.MouseToolbar());
      map.addLayer(mandelbrot_grid);
      if (!map.getCenter()) {
        map.zoomToExtent(new OpenLayers.Bounds(-125.903320312,0.263671875,-125.859375000,0.307617188));
      }
  },

  '#gallery_content' : function (element) {
    myLightbox = new Lightbox();
  }
};

Behaviour.register(rules);
