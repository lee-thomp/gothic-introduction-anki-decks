.DEFAULT_GOAL := all

venv := $(if $(wildcard .venv/bin/python),.venv,.)
python := $(venv)/bin/python
hy2py := $(venv)/bin/hy2py

# The substitution here gets around some awkward handling of spaces in file
# names within Make
sources := $(subst Lesson 1,Lesson\ 1,$(wildcard Gothic/*.txt Gothic/*/*.txt Gothic/*/*/*.txt))
tsvs := $(subst .txt,.tsv,$(sources))
# Directory mtimes also catch removals from the wildcard source list
source_dirs := $(subst Lesson 1,Lesson\ 1,$(wildcard Gothic/ Gothic/*/ Gothic/*/*/))

.PHONY: all
all: Gothic.apkg

%.tsv: %.txt org-table-anki.el table-to-tsv.sh
	./table-to-tsv.sh "$<" "$@"

# Hy 1.3.1's file runner fails with Python 3.12.3; hy2py avoids that path.
build/build_anki.py: build_anki.hy
	mkdir -p $(@D)
	$(hy2py) --output "$@" "$<"

Gothic.apkg: $(tsvs) $(source_dirs) build/build_anki.py anki.css
	$(python) build/build_anki.py -o "$@" $(tsvs)
