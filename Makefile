RM_RF:=rm -Rf
MKDIR_P:=mkdir -p
COPY:=cp
PYTHON3?=python
DOS2UNIX?=dos2unix

ROSE2ARC=./bin/rose2arc.py
VASM=./bin/vasmarm_std_win32.exe -m250 -Fbin -opt-adr
SHRINKLER=./bin/shrinkler.exe -p -d

ARCULATOR_HOSTFS=../../Arculator_V2.1_Windows/hostfs

##########################################################################
##########################################################################

.PHONY:all
all: shrinkler

.PHONY:clean
clean:
	$(RM_RF) build

##########################################################################
##########################################################################

SHRINKLER_ARC=shrinkler,ff8

.PHONY:shrinkler
shrinkler: $(ARCULATOR_HOSTFS)/$(SHRINKLER_ARC)

build/shrinkler.bin: src/main.asm src/arc-shrinkler.asm build/test.shri
	$(MKDIR_P) build
	$(VASM) -L build/compile.txt -o build/shrinkler.bin src/main.asm

build/test.shri: data/waytoorude.bin #data/a252eur3.txt
	$(MKDIR_P) build
	$(SHRINKLER) $< $@

$(ARCULATOR_HOSTFS)/$(SHRINKLER_ARC): build/shrinkler.bin
	$(RM_RF) $(ARCULATOR_HOSTFS)/$(SHRINKLER_ARC)
	cp build/shrinkler.bin $(ARCULATOR_HOSTFS)/$(SHRINKLER_ARC)