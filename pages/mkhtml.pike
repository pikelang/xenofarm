
void layout_chapter(string in) {
  array ps = in/"\n\n";

  write("<h2>"+ps[0]+"</h2>\n\n");

  int ol;

  foreach(ps[1..], string p) {

    // Deal with ol lists.
    if( sscanf(p, " %d. %s", int num, string rest)==2 &&
	num==ol+1 ) {
      if(!ol) write("<ol>\n");

      // Deal with unparagraphed ol lists.
      if(num==1 && sscanf(rest, "%*s\n 2. ")) {
	write("<li>");
	foreach(rest/"\n", string line) {
	  if( sscanf(line, " %*d. %s", line)==2 )
	    write("</li>\n<li>"+line+"\n");
	  else
	    write(line+"\n");
	}
	write("</li>\n</ol>\n\n");
	continue;
      }

      write("<li>"+rest+"<br /><br /></li>\n\n");
      ol++;
      continue;
    }
    else if(ol) {
      write("</ol>\n\n");
      ol=0;
    }

    // Double spaces -> ASCII art.
    if(has_value(p, "  "))
      p = "<pre>"+p+"</pre>";

    write("<p>\n"+p+"\n</p>\n\n");
  }

  if(ol) write("</ol>\n\n");
}

mapping links = ([
  "Martin Nilsson" : "http://www.lysator.liu.se/~mani/",
  "Tinderbox" : "http://tinderbox.mozilla.org/",
  "Mozilla" : "http://www.mozilla.org/",
  "Pike" : "http://pike.ida.li.se/",
  "Python" : "http://www.python.org/",
  "Perl" : "http://www.perl.com/",
  "Java" : "http://java.sun.com/",
  "LOGO" : "http://el.media.mit.edu/logo-foundation/",
  "GNU GPL" : "http://www.gnu.org/copyleft/gpl.html",
  "Roxen WebServer" : "http://download.roxen.com/",
  "Roxen Interet Software" : "http://www.roxen.com/",
]);

void main(int n, array(string) args) {
  string fn = "README";
  if(n>1)
    fn = args[1];

  foreach(links; string from; string to)
    links[from] = sprintf("<a href='%s'>%s</a>", to, from);

  array chapters;
  {
    string file = Stdio.read_file(fn);
    file = String.trim_all_whites(file);
    file = _Roxen.html_encode_string(file);
    file = replace(file, links);
    chapters = file / "\n\n\n";
  }

  // Special case for contents chapter...
  chapters = chapters[1..];

  foreach(chapters, string chapter)
    layout_chapter(chapter);

}
