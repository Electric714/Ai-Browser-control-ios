# <img src="Resources/icon.png" alt="logo" width="30px" height="30px" /> Telescopure

WiOS is a browser for iOS which has AI LLM function to control your bowser via api .<br>
You can use Telescopure to debug your application that work with the browser.




## Functions
- Open Router Ai Api compatible
- sends a wuery to the llm to have the AI control the browser autonomiously
- Settable as default browser.
- Open an HTTP or HTTPS link.
- Search by keywords.
- Browse a page in the full screen.
- Pull to refresh a page.
- Page Zoom.
- Bookmark user's favorite page.
- Open a link of other app in Telescopure.
- User can select a search engine (Google/Bing/DuckDuckGo).
- Support light and dark themes.

## Requirements

- Written in Swift 6.2
- Compatible with iOS 26.2+
- Development with Xcode 26.2

## Supported languages

- English (primary)


## Screenshots

<div>
  <img src="Resources/1-browsing-1.png" alt="browsing" width="150px" />
  <img src="Resources/2-browsing-2.png" alt="full screen" width="150px" />
  <img src="Resources/3-bookmark.png" alt="bookmark" width="150px" />
  <img src="Resources/4-settings-1.png" alt="settings" width="150px" />
</div>

<div>
  <img src="Resources/5-settings-2.png" alt="set as default browser" width="150px" />
  <img src="Resources/6-settings-3.png" alt="select search engine" width="150px" />
  <img src="Resources/7-share-link-1.png" alt="share link 1" width="150px" />
  <img src="Resources/8-share-link-2.png" alt="share link 2" width="150px" />
</div>

## Implementation

- SwiftUI based ai browser App
- WKWebView wrapped in UIViewRepresentable
- Share Extension

## Tree

```plain
.
├── LocalPackage
│   ├── Package.swift
│   ├── Sources
│   │   ├── DataSource
│   │   ├── Model
│   │   └── UserInterface
│   └── Tests
│       └── ModelTests
├── Telescopure
│   ├── Assets.xcassets
│   ├── Info.plist
│   ├── InfoPlist.xcstrings
│   ├── Settings.bundle
│   └── TelescopureApp.swift
├── Telescopure.xcodeproj
├── Telescopure.xctestplan
├── TelescopureShare
│   ├── MainInterface.storyboard
│   ├── Info.plist
│   ├── InfoPlist.xcstrings
│   └── ShareViewController.swift
└── TelescopureUITests
    └── TelescopureUITests.swift
```
