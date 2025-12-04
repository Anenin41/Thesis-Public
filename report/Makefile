ABSOLUTE_PATH = /home/anenin/Documents/Git/thesis/report
TARGET = main
REPORT  = main.pdf
BIBLIO = $(ABSOLUTE_PATH)/references.bib
XFILES = main.tex intro.tex models.tex rainfall.tex runoff.tex numerics.tex simulations.tex

# Add <file.tex> if you split the document into files.

all:  $(REPORT)

$(REPORT): $(XFILES) $(BIBLIO)

clean:
	rm -f $(TARGET).aux $(TARGET).bbl $(TARGET).blg $(TARGET).log \
	      $(TARGET).lot $(TARGET).out $(TARGET).toc $(TARGET).pdf


.SUFFIXES: .tex .pdf

.tex.pdf:
	pdflatex $(<:.tex=)
	bibtex   $(<:.tex=)
	pdflatex $(<:.tex=)
	pdflatex $(<:.tex=)
