#! /usr/bin/env pike

// Reads the multilayered Photoshop image file plupp.psd and then
// replaces the background color to the provided color, resizes the
// image and saves it as a GIF or PNG file.
//
// If it weren't for all this user friendliness this program would be
// four lines or so...

int main(int n, array(string) args) {
  if(n==1 || has_value(args, "--help")) {
    write(#"Usage: mkplupp.pike color [size] [png/gif]
Examples:
  mkplupp.pike green 20
  mkplupp.pike #ffcc00 16 gif
");
    return 0;
  }

  array layers = Image.PSD.decode_layers(Stdio.read_file("plupp.psd"));

  int size;
  Image.Color c = Image.Color(args[1]);
  layers[0] = Image.Layer(layers[0]->xsize(),layers[0]->ysize(),c);
  Image.Image res = Image.lay(layers)->image();

  if(n>2) {
    size = (int)args[2];
    if(size>res->xsize()) {
      werror("Size > original size (%d). It will look ugly.\n",
	     res->xsize());
    }
    if(size<1) {
      werror("Size must be greater than 0.\n");
      return 1;
    }
  }

  if(size)
    res = res->scale(size, 0);

  string format = "png";
  if(n==4) {
    format = lower_case(args[3]);
    if( !(< "png", "gif" >)[format] ) {
      werror("Only PNG and GIF formats are supported.\n");
      return 1;
    }
  }

  string name = "plupp_" + c->name() + "." + format;
  if(format=="gif")
    Stdio.write_file(name, Image.GIF.encode(res));
  else
    Stdio.write_file(name, Image.PNG.encode(res));
}
