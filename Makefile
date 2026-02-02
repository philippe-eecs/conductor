.PHONY: build run install clean

build:
	./scripts/build-app.sh

run: build
	open build/Conductor.app

install: build
	cp -r build/Conductor.app ~/Applications/

clean:
	rm -rf build .build
