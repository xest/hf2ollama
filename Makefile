DIR_ROOT := $(CURDIR)
DIR_APP := $(DIR_ROOT)/app
DIR_MODELS := $(DIR_ROOT)/models
DIR_STAMPS := $(DIR_ROOT)/stamps
DIR_README := $(DIR_ROOT)/readme.d

PRJ := $(notdir $(DIR_ROOT))
DOCKER_IMAGE := $(PRJ)-$(USER)
UID := $(shell id -u)
GID := $(shell id -g)
JOBS ?= $(shell echo $$((($$(nproc)+3)/4)))

HF_CACHE := .cache/huggingface
HF_MODEL_ID_DEFAULT := LGAI-EXAONE/EXAONE-3.0-7.8B-Instruct
HF_MODEL_ID ?= $(HF_MODEL_ID_DEFAULT)
HF_MODEL_NAME := $(subst /,_,$(HF_MODEL_ID))

QUANTIZE_METHOD_DEFAULT := Q4_K_M
QUANTIZE_METHOD ?= $(QUANTIZE_METHOD_DEFAULT)
MODEL_OFFICIAL := /models/$(HF_MODEL_ID)
MODEL_LLAMAFIED := /models/$(HF_MODEL_ID)-Llamafied
MODEL_CONVERTED := /models/$(HF_MODEL_ID)-Llamafied.gguf
MODEL_QUANTIZED := /models/$(HF_MODEL_ID)-Llamafied-$(QUANTIZE_METHOD).gguf

OLLAMA_IMAGE := ollama/ollama
OLLAMA_MODEL_DEFAULT := $(HF_MODEL_NAME)
OLLAMA_MODEL ?= $(OLLAMA_MODEL_DEFAULT)
OLLAMA_MODEL_FILE_TEMPLATE := Modelfile.$(HF_MODEL_NAME)
OLLAMA_MODEL_FILE := $(MODEL_QUANTIZED).modelfile
OLLAMA_HOST_DEFAULT := http://host.docker.internal:11434
OLLAMA_HOST ?= $(OLLAMA_HOST_DEFAULT)
OLLAMA_MODELS ?= nomic-embed-text hermes3 llama3.1 mistral-nemo glm4 internlm2 gemma2 qwen2 deepseek-v2 aya

SERVER_HOST := 0.0.0.0
SERVER_PORT := 8000

define HELP_HEADING
(echo; echo $(1); printf "%$$(echo -n $(1) | wc -c)s\n" | sed "s/ /-/g")
endef

define HELP
printf "* %-20s : %s\n" $(1) $(2)
endef

define DOCKER_BUILD
DOCKER_BUILDKIT=1 docker build --target $(1)\
	-t $(DOCKER_IMAGE):$(1) \
	--build-arg UID=$(UID) \
	--build-arg GID=$(GID) \
	--build-arg JOBS=$(JOBS) \
	$(DIR_ROOT)
endef

define DOCKER_RUN
docker run \
	--name $(DOCKER_IMAGE)-build \
	--rm \
	--gpus all \
	-v $(HOME)/$(HF_CACHE):/home/app/$(HF_CACHE) \
	-v ./models:/models \
	-e UID=$(UID) \
	-e GID=$(GID) \
	-e HF_MODEL_ID=$(HF_MODEL_ID) \
	-e QUANTIZE_METHOD=$(QUANTIZE_METHOD) \
	-e MODEL_OFFICIAL=$(MODEL_OFFICIAL) \
	-e MODEL_LLAMAFIED=$(MODEL_LLAMAFIED) \
	-e MODEL_CONVERTED=$(MODEL_CONVERTED) \
	-e MODEL_QUANTIZED=$(MODEL_QUANTIZED) \
	-e OLLAMA_MODEL_FILE_TEMPLATE=$(OLLAMA_MODEL_FILE_TEMPLATE) \
	-e OLLAMA_MODEL_FILE=$(OLLAMA_MODEL_FILE) \
	$(1) \
	$(DOCKER_IMAGE):build \
	$(2)
endef

define DOCKER_OLLAMA_RUN
docker run \
	--name $(DOCKER_IMAGE)-ollama \
	--rm \
	--add-host=host.docker.internal:host-gateway \
	-v ./models:/models \
	$(1) \
	$(OLLAMA_IMAGE) \
	$(2)
endef

define DOCKER_OLLAMA_RUN_REMOTE
$(call DOCKER_OLLAMA_RUN,-e OLLAMA_HOST=$(OLLAMA_HOST) $(1),$(2))
endef

ifeq ($(V),)
.SILENT:
endif

.PHONY: all help build download llamafy convert quantize create run \
	readme shell ollama-shell ollama-pull clean distclean \
	server

all: help

help:
	$(call HELP_HEADING,"Environment Variables")
	$(call HELP,HF_MODEL_ID,"Hugging Face Model ID (default: $(HF_MODEL_ID_DEFAULT))")
	$(call HELP,QUANTIZE_METHOD,"Quantize method (default: $(QUANTIZE_METHOD_DEFAULT))")
	$(call HELP,OLLAMA_MODEL,"Ollama model name (default: $(OLLAMA_MODEL_DEFAULT))")
	$(call HELP,OLLAMA_HOST,"Ollama host url (default: $(OLLAMA_HOST_DEFAULT))")
	$(call HELP_HEADING,"Targets")
	$(call HELP,"make build","Build a docker image for building")
	$(call HELP,"make download","Download the official model from Hugging Face")
	$(call HELP,"make llamafy","Llamafy the official model")
	$(call HELP,"make convert","Convert the Llamafied model to a gguf model")
	$(call HELP,"make quantize","Quantize the gguf model")
	$(call HELP,"make create","Create a model that can be used in Ollama")
	$(call HELP,"make run","Run Ollama CLI")
	$(call HELP,"make server","Build a docker image for server")
	$(call HELP_HEADING,"Development Targets")
	$(call HELP,"make readme","Update README.md")
	$(call HELP,"make shell","Run a shell of the docker image for build")
	$(call HELP,"make ollama-shell","Run a shell of the Ollama docker image")
	$(call HELP,"make ollama-pull","Pull Ollama models")
	$(call HELP,"make clean","Delete the docker images for building")
	$(call HELP,"make distclean","Delete the docker images for building and all the files generated")

build: $(DIR_STAMPS)/built
$(DIR_STAMPS)/built: $(DIR_ROOT)/Dockerfile $(wildcard $(DIR_APP)/*)
	$(call DOCKER_BUILD,build)
	touch $@

download: build $(DIR_STAMPS)/downloaded.$(HF_MODEL_NAME)
$(DIR_STAMPS)/downloaded.$(HF_MODEL_NAME):
	$(call DOCKER_RUN,,./main.sh download)
	touch $@

llamafy: download $(DIR_STAMPS)/llamafied.$(HF_MODEL_NAME)
$(DIR_STAMPS)/llamafied.$(HF_MODEL_NAME):
	$(call DOCKER_RUN,,./main.sh llamafy)
	touch $@

convert: llamafy $(DIR_STAMPS)/converted.$(HF_MODEL_NAME)
$(DIR_STAMPS)/converted.$(HF_MODEL_NAME):
	$(call DOCKER_RUN,,./main.sh convert)
	touch $@

quantize: convert $(DIR_STAMPS)/quantized.$(HF_MODEL_NAME)
$(DIR_STAMPS)/quantized.$(HF_MODEL_NAME):
	$(call DOCKER_RUN,,./main.sh quantize)
	touch $@

modelfile: build
	$(call DOCKER_RUN,,./main.sh modelfile)

create: quantize modelfile
	$(call DOCKER_OLLAMA_RUN_REMOTE,,create $(OLLAMA_MODEL) -f $(OLLAMA_MODEL_FILE))

run:
	$(call DOCKER_OLLAMA_RUN_REMOTE,-it,run $(OLLAMA_MODEL))

server: $(DIR_STAMPS)/server
$(DIR_STAMPS)/server: $(DIR_ROOT)/Dockerfile $(wildcard $(DIR_APP)/*)
	$(call DOCKER_BUILD,server)
	touch $@

readme: $(DIR_ROOT)/README.md
$(DIR_ROOT)/README.md: $(DIR_ROOT)/Makefile $(wildcard $(DIR_README)/*)
	echo "# $(PRJ)" >$@
	cat $(DIR_README)/summary.md >>$@
	$(call HELP_HEADING,"Flowchart") >>$@
	cat $(DIR_README)/flowchart.md >>$@
	$(MAKE) -s help >>$@ 2>/dev/null
	$(call HELP_HEADING,"Tested Models") >>$@
	cat $(DIR_README)/models.md >>$@
	$(call HELP_HEADING,"References") >>$@
	cat $(DIR_README)/references.md >>$@
	git diff $@

shell: build
	$(call DOCKER_RUN,-it)

ollama-shell:
	$(call DOCKER_OLLAMA_RUN,-d) >/dev/null
	docker exec -it $(DOCKER_IMAGE)-ollama \
		/bin/sh -c "export OLLAMA_HOST=$(OLLAMA_HOST) && exec /usr/bin/bash"
	docker stop $(DOCKER_IMAGE)-ollama >/dev/null

ollama-pull:
	$(foreach model,$(OLLAMA_MODELS),echo "* $(model)" && $(call DOCKER_OLLAMA_RUN_REMOTE,,pull $(model));)

clean:
	-rm -f $(DIR_STAMPS)/*
	-rm -rf $(DIR_MODELS)/*/*-Llamafied*
	-docker rmi $(DOCKER_IMAGE):build $(DOCKER_IMAGE):server $(OLLAMA_IMAGE)

distclean: clean
	rm -rf $(DIR_MODELS)/*
