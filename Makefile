#
# $Id: Makefile,v 1.1 2002/12/01 15:37:40 mani Exp $
#

USER=mani
SERVER=proton.lysator.liu.se
.PHONY : website

website: pages/web/documentation.html
	scp pages/web/* $(USER)@$(SERVER):/lysator/www/projects/xenofarm

pages/web/documentation.html: README pages/mkhtml.pike
	pike pages/mkhtml.pike README > pages/web/documentation.xml