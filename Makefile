.PHONY: build test run app clean

build:
	swift build

test:
	swift test

run:
	swift run DeepSeekUsage

app: build
	rm -rf ".build/DeepSeek Usage.app"
	mkdir -p ".build/DeepSeek Usage.app/Contents/MacOS" ".build/DeepSeek Usage.app/Contents/Resources"
	cp ".build/debug/DeepSeekUsage" ".build/DeepSeek Usage.app/Contents/MacOS/DeepSeekUsage"
	cp "Resources/AppIcon.icns" ".build/DeepSeek Usage.app/Contents/Resources/AppIcon.icns"
	printf '%s\n' \
	'<?xml version="1.0" encoding="UTF-8"?>' \
	'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	'<plist version="1.0"><dict>' \
	'<key>CFBundleExecutable</key><string>DeepSeekUsage</string>' \
	'<key>CFBundleIdentifier</key><string>local.deepseek.usage</string>' \
	'<key>CFBundleName</key><string>DeepSeek Usage</string>' \
	'<key>CFBundleIconFile</key><string>AppIcon</string>' \
	'<key>CFBundlePackageType</key><string>APPL</string>' \
	'<key>CFBundleShortVersionString</key><string>1.0.0</string>' \
	'<key>CFBundleVersion</key><string>1</string>' \
	'<key>LSMinimumSystemVersion</key><string>26.0</string>' \
	'<key>LSUIElement</key><true/>' \
	'<key>NSHighResolutionCapable</key><true/>' \
	'</dict></plist>' > ".build/DeepSeek Usage.app/Contents/Info.plist"
	@echo ".build/DeepSeek Usage.app"

clean:
	rm -rf .build
