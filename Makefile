USER=mani
SERVER=nazgul.lysator.liu.se
.PHONY : publish preview website clean

all:
	@echo Please specify the target you need.
	@echo 
	@echo Note: this makefile is only used to publish the web pages at
	@echo http://www.lysator.liu.se/xenofarm/. Please read README if you
	@echo want to set up your own Xenofarm project, or client/README if
	@echo you want to run a client.  In neither case will you be using
	@echo this Makefile.

publish: website
	scp build/web/* $(USER)@$(SERVER):/lysator/www/projects/xenofarm

preview: website
	scp build/web/* \
	  $(USER)@$(SERVER):/lysator/www/projects/xenofarm/preview

website: build/web build/web/documentation.xml \
	 build/client.tar.gz build/web/download.xml build/web/about.xml
	cp pages/web/*.xml build/web
	cp pages/web/*.gif build/web
	cp pages/web/template build/web
	cp build/client.tar.gz build/web

build/web/about.xml: build/web README pages/mkhtml.pike
	pike pages/mkhtml.pike --about README > build/web/about.xml

build/web/documentation.xml: build/web README pages/mkhtml.pike
	pike pages/mkhtml.pike README > build/web/documentation.xml

build/web/download.xml: build/web pages/web/download.xml.in \
	                build/client.tar.gz
	pike -e 'object s=file_stat("build/client.tar.gz"); \
	  object t=Calendar.Second(s->mtime); \
	  string x=sprintf("%s, %s %s", String.int2size(s->size), \
	    t->format_ymd(), t->format_tod()); \
	  Stdio.write_file("build/web/download.xml", \
	    replace(Stdio.read_file("pages/web/download.xml.in"), \
	      "@info@", x));'

build/client.tar.gz: build
	@if [ -f client/Makefile ] ; then cd client && $(MAKE) spotless; \
	  else : ; fi
	-rm -r build/client
	-rm build/client.tar
	-rm build/client.tar.gz
	cp -R client build
	-rm build/client/config/*.cfg
	-rm build/client/config/*~
	-rm build/client/config/contact.txt
	-mkdir build/client/projects
	@for p in projects/*; do \
	  if [ -f "$$p/README" ] ; then \
	    mkdir "build/client/$$p"; \
	    cp "$$p/README" "build/client/$$p"; \
	    cp $$p/*.cfg "build/client/$$p"; \
	  else \
	    echo "No README found in project $$p."; \
	  fi \
	done
	find build/client -name Root | xargs pike -e \
	  'Stdio.write_file(argv[1..][*], \
	  ":pserver:anonymous@cvs.lysator.liu.se:/cvsroot/xenofarm");'
	cd build && tar c client > client.tar
	cd build && gzip -9 client.tar

build:
	-mkdir build

build/web: build
	-mkdir build/web

clean:
	-rm -r build
	-rm pages/web/documentation.xml
	-rm pages/web/client.tar.gz
