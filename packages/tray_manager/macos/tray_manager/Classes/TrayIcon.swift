//
//  TrayIcon.swift
//  tray_manager
//
//  Created by Lijy91 on 2022/5/15.
//

import AppKit

public class TrayIcon: NSObject {
    public var onTrayIconMouseDown:(() -> Void)?
    public var onTrayIconMouseUp:(() -> Void)?
    public var onTrayIconRightMouseDown:(() -> Void)?
    public var onTrayIconRightMouseUp:(() -> Void)?

    var statusItem: NSStatusItem?

    public override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.imagePosition = .imageLeft
        button.cell?.wraps = true
        button.cell?.lineBreakMode = .byWordWrapping
        button.target = self
        button.action = #selector(statusItemButtonClicked(_:))
        button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp])
    }

    public func setImage(_ image: NSImage, _ imagePosition: String) {
        statusItem?.button?.image = image
        setImagePosition(imagePosition)
    }

    public func setImagePosition(_ imagePosition: String) {
        statusItem?.button?.imagePosition = imagePosition == "right"
            ? NSControl.ImagePosition.imageRight
            : NSControl.ImagePosition.imageLeft
    }

    public func removeImage() {
        statusItem?.button?.image = nil
    }

    public func setTitle(_ title: String) {
        guard let button = statusItem?.button else { return }
        if title.isEmpty {
            button.title = ""
            return
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        if title.contains("\n") {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.minimumLineHeight = 9
            paragraphStyle.maximumLineHeight = 9
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    NSAttributedString.Key.font: font,
                    NSAttributedString.Key.foregroundColor: NSColor.labelColor,
                    NSAttributedString.Key.paragraphStyle: paragraphStyle,
                    NSAttributedString.Key.baselineOffset: -5.0,
                ]
            )
        } else {
            button.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    NSAttributedString.Key.font: font,
                    NSAttributedString.Key.foregroundColor: NSColor.labelColor,
                ]
            )
        }
    }

    public func setToolTip(_ toolTip: String) {
        statusItem?.button?.toolTip = toolTip
    }

    @objc func statusItemButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        switch event.type {
        case .leftMouseDown:
            onTrayIconMouseDown?()
        case .leftMouseUp:
            onTrayIconMouseUp?()
        case .rightMouseDown:
            onTrayIconRightMouseDown?()
        case .rightMouseUp:
            onTrayIconRightMouseUp?()
        default:
            break
        }
    }
}
