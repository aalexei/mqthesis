##################################################################
#
# LaTeX / PDFLaTeX Makefile
# (c) Tom Bobach 2007
# (c) Alexei Gilchrist 2008-2025
#
# History:
#   22-03-2025  (AG) Specialised to pdf.
#   24-09-2008  (AG) Stripped away some of the more dangerous code
#   17-07-2007  (TB) Added 2-levels of recursion for include checks
#   09-05-2007  (TB) Initial Version
#
# Disclaimer:
#   Use at your own risk.
#   I take no responsibility for this Makefile eating up your most
#   precious work, teaching your baby bad language or evoking evil
#   ghosts.
#
# What happens:
#   The current directory is searched for a *.tex file containing
#   the string "\documentclass"; this will be the main file.
#   All files included in the main file via "\include" will be
#   added to the source files.
#
#   If any of the input files contains the string "\bibliographystyle",
#   bibtex is invoked, the make dependency linked to the bib file found
#   in the "\bibliography{<file>}" entry.
#
# Usage:
#   make info        Prints some info about the setup, what is considered
#                    the main file, what is the bibliography, what are
#                    the relevant images etc.
#   make clean       Removes typical intermediate files.
#   make [pdf]       Runs as stated in the beginning, assuming as target
#                    a pdf named after the main file.
#   make watch       Checks every second for changes in *.tex, and *.bib
#
#
# TODO:
#   - support an arbitrary number of levels of recursion (currently 2)
#   - strip the comments from the texfile for every analysis of the text
#     (currently only done for bib file inclusion)
##################################################################

##################################################################
#   Main definitions - place your customizations here
##################################################################

MAINFILE=$(shell grep -l "\\\\documentclass" *.tex)

##################################################################
#   Some Definitions that should not need change
##################################################################

ifneq ($(words $(MAINFILE)),1)
$(error For automatic main file detection, only one .tex file can contain the "\documentclass" string. run make MAINFILE=<your mainfile>)
endif
# Currently, only two levels of recursion for included input is supported.
# If you need more, extend as you like after the scheme below.
TEXFILESPRE:=\
  $(shell grep "\\\\include{" $(MAINFILE) | sed 's/.*{\([^}]*\)}.*/\1/g') \
  $(shell egrep "\\\\input{.*}" $(MAINFILE) | sed 's/.*{\([^}]*\)}.*/\1/g')

ifneq ($(words $(TEXFILESPRE)),0)
  TEXFILES:=\
    $(MAINFILE:.tex=)\
    $(TEXFILESPRE)\
    $(shell grep "\\\\include{" $(TEXFILESPRE:=.tex) | sed 's/.*{\([^}]*\)}.*/\1/g') \
    $(shell egrep "\\\\input{.*}" $(TEXFILESPRE:=.tex) | sed 's/.*{\([^}]*\)}.*/\1/g')
else
  TEXFILES:=$(MAINFILE:.tex=) $(TEXFILESPRE)
endif


MUTE=@
SILENT=> /dev/null
VERYSILENT=1> /dev/null 2>/dev/null

MAKE=make --no-print-directory
LS=ls -1 --color=none
CP=cp

LATEX=pdflatex -shell-escape -interaction=nonstopmode
BIBTEX=bibtex

MSG_LAB_CHANGED="LaTeX Warning: Label(s) may have changed"
MSG_REF_UNDEFINED="LaTeX Warning: Reference.*undefined on input line.*"
MSG_CIT_UNDEFINED="LaTeX Warning: Citation.*undefined on input"

# strip all comments and extract the bibliography
FIND_BIB_FILE=$(shell \
	sed -e "s/\\\\%//g" $(1) | \
	sed -e "s/\([^%]*\).*/\1/g" | \
	grep "\\\\bibliography{"  | \
        sed 's/.*{\([^}^ ]*\)}.*/\1/g').bib

BIBFILE:=$(call FIND_BIB_FILE, $(TEXFILES:=.tex))
ifneq ($(BIBFILE),.bib)
  ifneq ($(wildcard *.bib),)
    BBL:=$(MAINFILE:.tex=.bbl)
  endif
endif


##################################################################
#   All the shell magic that helps us manage the twisted LaTeX
#   Compilation procedure
##################################################################


clear_valid=( [ ! -e .make_valid ] || $(RM) .make_valid )
check_undef_citations=\
  ( egrep $(MSG_CIT_UNDEFINED) $(MAINFILE:.tex=.log) > /dev/null )

# determine the changeset for citations
define check_citationchange
	(                                                \
	  [ -e .make_citations ] || touch .make_citations ;        \
	  ( grep "\\citation" $(MAINFILE:.tex=.aux)      \
		| sort                                   \
		| uniq                                   \
		| diff .make_citations -                      \
		> .make_citediff                              \
	  )                                              \
	)
endef

# exctract the citations from the aux file
define make_citations
	(                                                   \
	  (                                                 \
	    [ -e $(MAINFILE:.tex=.aux) ] &&                 \
	    ( echo "[info] Extracting citations...";        \
		grep "\\citation" $(MAINFILE:.tex=.aux)     \
		| sort                                      \
		| uniq                                      \
		> .make_citations                                \
	    )                                               \
	  )                                                 \
	  || touch .make_citations                               \
	)
endef

# comparing the citations in $(MAINFILE:.tex=.aux)
# against those in .make_citations.
# if there are differences, .citediff is changed.
define make_citediff
	(                                                     \
	  ( [ -e .make_citations ] || touch .make_citations ;           \
	    [ -e .make_citediff  ] || touch .make_citediff ;            \
	    echo "[info] Checking for changed Citations..." ; \
	    grep "\\citation" $(MAINFILE:.tex=.aux)           \
		| sort                                        \
		| uniq                                        \
		| diff .make_citations -                           \
	    > .make_citediff__                                     \
	  )                                                   \
	  || mv .make_citediff__ .make_citediff                         \
	)
endef

# compiles the document
# the file .make_valid is created if the compilation went without
# errors
define runtexonce
  ( 	                                                    \
    $(clear_valid);                                         \
    ( $(LATEX) $(MAINFILE) $(SILENT) &&                     \
      touch .make_valid );                                       \
    (                                                       \
      ( egrep $(MSG_REF_UNDEFINED) $(MAINFILE:.tex=.log)    \
        > .make_undefref ) ;                                     \
      ( egrep $(MSG_CIT_UNDEFINED) $(MAINFILE:.tex=.log)    \
        > .make_undefcit ) ;                                     \
      true                                                  \
    )                                                       \
  )
endef

# compile the document as many times as necessary to
# have cross-references right
define runtex
(                                                                      \
  echo "[info] Running tex...";                                        \
  $(runtexonce);                                                       \
  while( grep $(MSG_LAB_CHANGED) $(MAINFILE:.tex=.log) > /dev/null ) ; \
  do                                                                   \
      echo "[info] Rerunning tex...";                                  \
      $(runtexonce);                                                   \
  done                                                                 \
)
endef

##################################################################
#   Main compilation rules
##################################################################

pdf: $(MAINFILE:.tex=.pdf)


$(MAINFILE:.tex=.pdf): .make_compilesource
	$(MUTE)echo "[info] Created PDF."

.make_compilesource: .make_force
	$(MUTE)$(MAKE) .make_valid
	$(MUTE)[ -z "$(BBL)" ] || $(MAKE) .make_citations
	$(MUTE)[ -e .make_valid ] || (                                    \
	  ( [ -e .make_compiled ] || $(MAKE) .make_compiled ) ;                \
	  ( [ -e .compiled ] || $(MAKE) .compiled ) ;                \
	  ( [ -e .compiled ] || $(MAKE) .compiled ) ;                \
	  ( [ -e .compiled ] || echo "[Error] Could not make it work after 3 runs. Weird." ) \
	)
	$(MUTE) (                                                    \
           echo ; echo "Compilation Warnings:" ;                     \
	   grep "Warning" $(MAINFILE:.tex=.log) ;                    \
	   grep "Error" $(MAINFILE:.tex=.log) ;                      \
	   grep -A 1 "Undefined" $(MAINFILE:.tex=.log) || true       \
	)
	$(MUTE)[ ! -e $(MAINFILE:.tex=.bbl) ] || (                   \
	  echo ; echo "Bibtex Warnings:" ;                           \
	  grep "Warning" $(MAINFILE:.tex=.blg) ;                     \
	  grep "Error" $(MAINFILE:.tex=.blg) || true                 \
	)
	$(MUTE)[ -z "$(BBL)" -a -e .make_valid ] || [ -n "$(BBL)" -a -e .make_compiled ]


clean:
	$(MUTE)$(RM) *.bbl *.blg *.aux *.log *.toc *.lof *.lot *.out
	$(MUTE)$(RM) .make_valid .make_citations .make_citediff .make_undefcit .make_undefref .make_compiled .make_force


info:
	@echo Main file:    $(MAINFILE)
	@echo Input files:  $(TEXFILES:=.tex)
	@echo Bibliography: $(BIBFILE)

# just do one run...
.make_valid: $(TEXFILES:=.tex)
	$(MUTE)$(runtex)

# if citations changed since last run of bibtex, run it again.
.make_citations: .make_citediff $(BIBFILE)
	$(MUTE)[ ! -e .make_compiled ] || rm .make_compiled
	$(MUTE)(                         \
	  echo "[info] Running BibTex" ; \
	  bibtex $(MAINFILE:.tex=) $(SILENT)         \
	) && $(make_citations)
	$(MUTE) $(clear_valid)

.make_citediff: .make_force
	$(MUTE)$(make_citediff)

# run as long as necessary
.make_compiled: $(TEXFILES:=.tex) $(BBL) 
	$(MUTE)echo "Found undefined Citations, rerunning..."
	$(MUTE)$(runtex)
	$(MUTE)$(check_undef_citations) || touch .make_compiled

.make_force:

define runwatch
  $(MUTE)CHANGE=true && while true ; \
  do       \
    if $$CHANGE ; then                             \
      echo;                             \
      echo "#######################################"; \
      echo "#    RUNNING MAKE                     #"; \
      echo "#######################################"; \
      echo;                                       \
      make;                                        \
      for i in $(TEXFILES:=*.tex) $(BIBFILE) ; do   \
        touch .$$i -r $$i;                         \
      done;                                        \
      CHANGE=false;                                \
    fi;                                            \
    sleep 2;                                       \
    echo 'tic' ; \
    for i in $(TEXFILES:=*.tex) $(BIBFILE) ; do     \
      if [ .$$i -ot $$i ] ; then                   \
        CHANGE=true;                               \
      fi                                           \
    done ;                                         \
  done
endef

watch:
	$(runwatch)
