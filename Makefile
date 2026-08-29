.PHONY: run doc html clean check tasks

GAP ?= gap
GAP_ARGS = -q --quitonbreak --packagedirs $(abspath .)

# run GAP and load the package
run:
	$(GAP) --packagedirs "$(abspath .);" -c 'LoadPackage("ArtifactManager");'

doc:
	$(GAP) $(GAP_ARGS) makedoc.g -c 'QUIT;'

html:
	NOPDF=1 $(GAP) $(GAP_ARGS) makedoc.g -c 'QUIT;'

clean:
	cd doc && rm -f *.{aux,bbl,blg,brf,css,dvi,html,idx,ilg,ind,js,lab,log,out,pdf,pnr,ps,six,tex,toc,txt,xml.bib} _*.xml title.xml

check:
	$(GAP) $(GAP_ARGS) tst/testall.g

# what is there to work on; see dev/tasks/README.md
tasks:
	@dev/tasks.sh
