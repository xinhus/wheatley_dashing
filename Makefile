.PHONY: serve

build:
	bundle install

serve: build
	GITHUB_ACCESS_TOKEN=`cat access_token` bundle exec rackup -p 8888
