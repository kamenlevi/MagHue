VERSION ?= 1.0.0

.PHONY: app install run zip clean

app:
	scripts/build-app.sh $(VERSION)

install: app
	rm -rf /Applications/MagHue.app
	cp -R dist/MagHue.app /Applications/MagHue.app
	@echo "installed to /Applications/MagHue.app"

run: app
	open dist/MagHue.app

zip: app
	cd dist && ditto -c -k --keepParent MagHue.app MagHue-$(VERSION).zip
	@echo "dist/MagHue-$(VERSION).zip"

clean:
	rm -rf .build dist
