import Foundation

enum LocatorBuilder {
    static func from(payload: ClickedElementPayload) -> Locator {
        Locator(
            primaryCSSSelector: payload.cssSelector,
            elementID: payload.elementID,
            tagName: payload.tagName,
            classes: payload.classes,
            ariaLabel: payload.ariaLabel,
            dataAttributes: payload.dataAttributes,
            textSnippet: payload.textSnippet,
            siblingIndex: payload.siblingIndex,
            parentTrail: payload.parentTrail,
            framePath: payload.framePath,
            shadowHostID: payload.shadowHostID
        )
    }
}
