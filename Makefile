SHELL := /bin/bash

default:
	echo 'please choose a target explicitly' && exit 1

push:
	aws s3 sync --exclude=.git/* . s3://crowdai-public/bootstrap
