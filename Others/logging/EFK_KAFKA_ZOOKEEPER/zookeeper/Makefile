TAG = v0.1
REGISTRY = reg.dhdc.com
USER = loggingefk
IMAGE = zookeeper

build:	
	docker build -t $(REGISTRY)/$(USER)/$(IMAGE):$(TAG) .
push:
	docker push $(REGISTRY)/$(USER)/$(IMAGE):$(TAG)
