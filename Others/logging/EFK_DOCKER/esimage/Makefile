TAG = v1.0.1
REGISTRY = reg.dhdc.com
USER = loggingefk
IMAGE_NAME = elasticsearch

build:	
	docker build -t $(REGISTRY)/$(USER)/$(IMAGE_NAME):$(TAG) .

push:
	docker  push $(REGISTRY)/$(USER)/$(IMAGE_NAME):$(TAG)
