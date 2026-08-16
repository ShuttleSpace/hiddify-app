//
//  TrayIcon.swift
//  tray_manager
//
//  Created by Lijy91 on 2022/5/15.
//

import AppKit

public class TrayIcon: NSView {
    public var onTrayIconMouseDown:(() -> Void)?
    public var onTrayIconMouseUp:(() -> Void)?
    public var onTrayIconRightMouseDown:(() -> Void)?
    public var onTrayIconRightMouseUp:(() -> Void)?

    var statusItem: NSStatusItem?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var iconSize = NSSize(width: 18, height: 18)
    private var titleText = ""
    private let titlePadding: CGFloat = 4
    private var labelWidthConstraint: NSLayoutConstraint?
    private var labelHeightConstraint: NSLayoutConstraint?

    public init() {
        super.init(frame: NSRect.zero)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        iconView.imageScaling = .scaleProportionallyDown
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        titleLabel.usesSingleLineMode = false
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.cell?.wraps = true
        titleLabel.cell?.isScrollable = false
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false

        guard let button = statusItem?.button else { return }
        button.image = nil
        button.title = ""
        button.imagePosition = .imageLeft

        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(iconView)
        button.addSubview(titleLabel)
        button.addSubview(self)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize.width),
            iconView.heightAnchor.constraint(equalToConstant: iconSize.height),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: titlePadding),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: button.topAnchor),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: button.bottomAnchor),
        ])

        labelWidthConstraint = titleLabel.widthAnchor.constraint(equalToConstant: 0)
        labelHeightConstraint = titleLabel.heightAnchor.constraint(equalToConstant: 0)
        labelWidthConstraint?.isActive = true
        labelHeightConstraint?.isActive = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setImage(_ image: NSImage, _ imagePosition: String) {
        iconView.image = image
        iconSize = image.size
        setImagePosition(imagePosition)
        layoutContent()
    }

    public func setImagePosition(_ imagePosition: String) {
        statusItem?.button?.imagePosition = imagePosition == "right"
            ? NSControl.ImagePosition.imageRight
            : NSControl.ImagePosition.imageLeft
    }

    public func removeImage() {
        iconView.image = nil
        layoutContent()
    }

    public func setTitle(_ title: String) {
        titleText = title
        let isMultiline = title.contains("\n")
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        titleLabel.maximumNumberOfLines = isMultiline ? 2 : 1
        titleLabel.lineBreakMode = isMultiline ? .byWordWrapping : .byClipping
        titleLabel.cell?.wraps = isMultiline
        titleLabel.attributedStringValue = NSAttributedString(
            string: title,
            attributes: [
                NSAttributedString.Key.font: font,
                NSAttributedString.Key.foregroundColor: NSColor.labelColor,
            ]
        )
        layoutContent()
    }

    public func setToolTip(_ toolTip: String) {
        statusItem?.button?.toolTip = toolTip
    }

    public override func mouseDown(with event: NSEvent) {
        statusItem?.button?.highlight(true)
        self.onTrayIconMouseDown!()
    }

    public override func mouseUp(with event: NSEvent) {
        statusItem?.button?.highlight(false)
        self.onTrayIconMouseUp!()
    }

    public override func rightMouseDown(with event: NSEvent) {
        self.onTrayIconRightMouseDown!()
    }

    public override func rightMouseUp(with event: NSEvent) {
        self.onTrayIconRightMouseUp!()
    }

    private func layoutContent() {
        guard let button = statusItem?.button else { return }
        titleLabel.isHidden = titleText.isEmpty
        if titleText.isEmpty {
            labelWidthConstraint?.constant = 0
            labelHeightConstraint?.constant = 0
            statusItem?.length = iconSize.width
            self.frame = button.bounds
            return
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        let isVertical = titleText.contains("\n")
        let widthReference = isVertical
            ? "↑999.99K0"
            : "↑999.99G  ↓999.99G"
        let widthReferenceText = NSAttributedString(
            string: widthReference,
            attributes: [NSAttributedString.Key.font: font]
        )
        let maxWidth = ceil(
            widthReferenceText.boundingRect(
                with: NSSize(width: 236, height: 40),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).size.width
        )
        let labelWidth = max(ceil(maxWidth), 1)
        let actualHeight = titleText.isEmpty
            ? 0
            : titleLabel.attributedStringValue.boundingRect(
                with: NSSize(width: labelWidth, height: 40),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
              ).size.height
        let labelHeight = ceil(actualHeight)
        labelWidthConstraint?.constant = labelWidth
        labelHeightConstraint?.constant = labelHeight
        statusItem?.length = iconSize.width + titlePadding + labelWidth
        self.frame = button.bounds
    }

    public override func layout() {
        super.layout()
        layoutContent()
    }
}
