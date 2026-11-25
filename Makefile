tables :=

include lesson-1/module.mk

tsvs := $(patsubst %.txt,%.tsv,$(tables))

%.tsv: %.txt
	./table-to-tsv.sh $< $@

deck: $(tsvs)
	: $^
