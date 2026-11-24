import UIKit

/// The layers button and the follow button at the top right of the map, as one Liquid Glass
/// capsule with a thin line between the buttons, as in Apple Maps.
final class MapControlsView: UIVisualEffectView {
    private static let buttonSize: CGFloat = 44

    init(layersButton: UIButton, followButton: UIButton) {
        // Interactive glass reacts to touches, as the system map controls do.
        let controlsGlassEffect = UIGlassEffect()
        controlsGlassEffect.isInteractive = true
        super.init(effect: controlsGlassEffect)
        translatesAutoresizingMaskIntoConstraints = false
        cornerConfiguration = .capsule()

        let buttonSeparator = UIView()
        buttonSeparator.backgroundColor = .separator

        let buttonStack = UIStackView(arrangedSubviews: [layersButton, buttonSeparator, followButton])
        buttonStack.axis = .vertical
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            buttonStack.topAnchor.constraint(equalTo: topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            layersButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            layersButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
            followButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
            buttonSeparator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
