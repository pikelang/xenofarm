
void layout_chapter(string in) {
  array ps = in/"\n\n";

  sscanf(ps[0], "%s ", string ch);
  write("<a name='"+ch+"'></a>");
  write("<h2>"+ps[0]+"</h2>\n\n");

  output_paragraphs(ps[1..]);
}

array parse_dl(string p) {
  array lines = p/"\n";
  if(sizeof(lines)<2) return 0;
  string one, two;
  sscanf(lines[1], "%[ ]%s", string w,two);
  two = w+two;
  int i = sizeof(w);
  if(!i) return 0;
  sscanf(lines[0], "%[ ]%s", w, one);
  if(sizeof(w)>=i) return 0;

  array out = ({ one, two });
  foreach(lines[2..], string line) {
    sscanf(line, "%[ ]", w, line);
    if(sizeof(w)<i) return 0;
    if(sizeof(w)>i) line = " "*(sizeof(w)-i)+line;
    out += ({ line });
  }
  return ({ i, out });
}

string dedent(string p, int ind) {
  string ret="";
  string tind = " "*ind;
  foreach(p/"\n", string line) {
    if(!sscanf(line, tind+"%s", line)) return 0;
    ret += line+"\n";
  }
  return ret;
}

void output_paragraphs(array(string) ps) {
  int ol, dl, ul;

  foreach(ps, string p) {

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

    // Deal with ul lists
    if( sscanf(p, " - %s", string rest) ) {
      if(!ul) {
	write("<ul>\n");
	ul=1;
      }
      write("<li>"+rest+"</li>\n");
      continue;
    }
    else if(ul) {
      write("</ul>\n\n");
      ul=0;
    }

    // Deal with dl lists.
    array pdl = parse_dl(p);
    if(pdl) {
      // Paragraph with first line less indented
      if(!dl) write("<dl>\n");
      dl = pdl[0];
      array lines = pdl[1];
      write("<dt><b>"+lines[0]+"</b></dt>");
      write("<dd>\n");
      output_paragraphs( ({ String.trim_all_whites(lines[1..][*])*"\n" }) );
      write("</dd>\n");
      continue;
    }
    else if(dl && has_prefix(p, " "*dl)) {
      string tmp = dedent(p, dl);
      if(tmp) {
	write("<dd>\n");
	output_paragraphs( ({ tmp }) );
	write("</dd>\n");
	continue;
      }
      else {
	write("</dl>\n\n");
	dl=0;
      }
    }
    else if(dl) {
      write("</dl>\n\n");
      dl=0;
    }

    // Double spaces -> ASCII art.
    if(has_value(p, "  "))
      p = "<pre>"+p+"</pre>";

    write("<p>\n"+p+"\n</p>\n\n");
  }

  if(ol) write("</ol>\n\n");
  if(ul) write("</ul>\n\n");
  if(dl) write("</dl>\n\n");
}

void make_about(array(string) data) {
  data = data[1]/"\n\n";

  foreach(links; string from; string to)
    links[from] = sprintf("<a href='%s'>%s</a>", to, from);

  write("<h2>"+data[0][3..]+"</h2>\n\n");

  foreach(data[1..], string p) {
    p = replace(p, links);
    if(has_value(p, "  "))
      p = (p/"\n")*"<br />\n";
    write("<p>"+p+"</p>\n\n");
  }
}

void make_doc(array(string) chapters) {
  write("<header>\n");
  {
    array lines = chapters[0]/"\n";
    write("<h2>"+lines[0]+"</h2>\n");
    write("<p>\n");
    foreach(lines[1..], string line) {
      if(sizeof(line)) {
	sscanf(line, "%[ ]%s", string w, line);
	sscanf(line, "%s ", string ch);
	write("%s<a href='#%s'>%s</a><br />\n",
	      "&nbsp;"*sizeof(w), ch, line);
      }
    }
    write("</p><br />\n");
  }
  write("</header>\n</tr><tr><td colspan='2'>\n");

  foreach(chapters[1..], string chapter)
    layout_chapter(chapter);
  write("</footer>\n");
}

mapping links = ([
  "Martin Nilsson" : "http://www.lysator.liu.se/~mani/",
  "Peter Bortas" : "http://peter.bortas.org/",
  "Per Hedbor" : "http://per.hedbor.org/",
  "Johan Schön" : "http://johan.schon.org/",
  "Tinderbox" : "http://tinderbox.mozilla.org/",
  "Mozilla" : "http://www.mozilla.org/",
  "Pike" : "http://pike.ida.liu.se/",
  "Python" : "http://www.python.org/",
  "Perl" : "http://www.perl.com/",
  "Java" : "http://java.sun.com/",
  "LOGO" : "http://el.media.mit.edu/logo-foundation/",
  "GNU GPL" : "http://www.gnu.org/copyleft/gpl.html",
  "Roxen WebServer" : "http://download.roxen.com/",
  "Roxen Internet Software" : "http://www.roxen.com/",
]);

void main(int n, array(string) args) {
  int(0..1) about = has_value(args, "--about");
  if(about) args -= ({ "--about" });

  string fn = "README";
  if(sizeof(args)>1)
    fn = args[1];

  array chapters;
  {
    string file = Stdio.read_file(fn);
    file = String.trim_all_whites(file);
    file = _Roxen.html_encode_string(file);
    chapters = file / "\n\n\n";
  }

  write("<use file='template'/>\n");

  if(about) {
    write("<header>\n\n");
    make_about(chapters);
    write("</header><footer/>\n");
  }
  else {
    make_doc(chapters);
  }
}
