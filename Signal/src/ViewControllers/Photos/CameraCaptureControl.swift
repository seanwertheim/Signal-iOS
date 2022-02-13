//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import UIKit
import SignalUI

protocol CameraCaptureControlDelegate: AnyObject {
    // MARK: Photo
    func cameraCaptureControlDidRequestCapturePhoto(_ control: CameraCaptureControl)

    // MARK: Video
    func cameraCaptureControlDidRequestStartVideoRecording(_ control: CameraCaptureControl)
    func cameraCaptureControlDidRequestFinishVideoRecording(_ control: CameraCaptureControl)
    func cameraCaptureControlDidRequestCancelVideoRecording(_ control: CameraCaptureControl)

    // MARK: Zoom
    var zoomScaleReferenceHeight: CGFloat? { get }
    func cameraCaptureControl(_ control: CameraCaptureControl, didUpdate zoomAlpha: CGFloat)
}

class CameraCaptureControl: UIView {

    private let shutterButtonOuterCircle = CircleBlurView(effect: UIBlurEffect(style: .light))
    private let shutterButtonInnerCircle = CircleView()

    private static let recordingLockControlSize: CGFloat = 36   // Stop button, swipe tracking circle, lock icon
    private static let shutterButtonDefaultSize: CGFloat = 72
    private static let shutterButtonRecordingSize: CGFloat = 122

    private var outerCircleSizeConstraint: NSLayoutConstraint!
    private var innerCircleSizeConstraint: NSLayoutConstraint!
    private var slidingCirclePositionContstraint: NSLayoutConstraint!

    private lazy var slidingCircleView: CircleView = {
        let view = CircleView(diameter: CameraCaptureControl.recordingLockControlSize)
        view.backgroundColor = .ows_white
        return view
    }()
    private lazy var lockIconView = LockView(frame: CGRect(origin: .zero, size: .square(CameraCaptureControl.recordingLockControlSize)))
    private lazy var stopButton: UIButton = {
        let button = OWSButton { [weak self] in
            guard let self = self else { return }
            self.didTapStopButton()
        }
        button.backgroundColor = .white
        button.dimsWhenHighlighted = true
        button.layer.masksToBounds = true
        button.layer.cornerRadius = 4
        button.alpha = 0
        return button
    }()

    weak var delegate: CameraCaptureControlDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        autoSetDimension(.height, toSize: CameraCaptureControl.shutterButtonDefaultSize)

        // Round Shutter Button
        addSubview(shutterButtonOuterCircle)
        outerCircleSizeConstraint = shutterButtonOuterCircle.autoSetDimension(.width, toSize: CameraCaptureControl.shutterButtonDefaultSize)
        shutterButtonOuterCircle.autoPin(toAspectRatio: 1)
        shutterButtonOuterCircle.autoVCenterInSuperview()
        shutterButtonOuterCircle.autoHCenterInSuperview()

        addSubview(shutterButtonInnerCircle)
        innerCircleSizeConstraint = shutterButtonInnerCircle.autoSetDimension(.width, toSize: CameraCaptureControl.shutterButtonDefaultSize)
        shutterButtonInnerCircle.autoPin(toAspectRatio: 1)
        shutterButtonInnerCircle.isUserInteractionEnabled = false
        shutterButtonInnerCircle.backgroundColor = .clear
        shutterButtonInnerCircle.layer.borderColor = UIColor.ows_white.cgColor
        shutterButtonInnerCircle.layer.borderWidth = 5
        shutterButtonInnerCircle.centerXAnchor.constraint(equalTo: shutterButtonOuterCircle.centerXAnchor).isActive = true
        shutterButtonInnerCircle.centerYAnchor.constraint(equalTo: shutterButtonOuterCircle.centerYAnchor).isActive = true

        // The long press handles both the tap and the hold interaction, as well as the animation
        // the presents as the user begins to hold (and the button begins to grow prior to recording)
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPressGesture.minimumPressDuration = 0
        shutterButtonOuterCircle.addGestureRecognizer(longPressGesture)
    }

    // MARK: - UI State

    enum State {
        case initial
        case recording
        case recordingLocked
    }

    private var _internalState: State = .initial
    var state: State {
        set {
            setState(newValue)
        }
        get {
            _internalState
        }
    }

    private var sliderTrackingProgress: CGFloat = 0 {
        didSet {
            if sliderTrackingProgress == 1 && state == .recording {
                setState(.recordingLocked) // this will call updateUIForCurrentState()
            } else {
                updateUIForCurrentState()
            }
        }
    }

    func setState(_ state: State, animationDuration: TimeInterval = 0) {
        guard _internalState != state else { return }

        Logger.debug("New state: \(_internalState) -> \(state)")

        _internalState = state
        if animationDuration > 0 {
            UIView.animate(withDuration: animationDuration,
                           delay: 0,
                           options: [ .beginFromCurrentState ],
                           animations: {
                self.updateUIForCurrentState()
            })
        } else {
            updateUIForCurrentState()
        }
    }

    private func updateUIForCurrentState() {
        switch state {
        case .initial:
            // element visibility
            if slidingCirclePositionContstraint != nil {
                stopButton.alpha = 0
                slidingCircleView.alpha = 0
                lockIconView.alpha = 0
                lockIconView.state = .unlocked
            }
            shutterButtonInnerCircle.alpha = 1
            shutterButtonInnerCircle.backgroundColor = .clear
            // element sizes
            outerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonDefaultSize
            innerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonDefaultSize

        case .recording:
            prepareRecordingControlsIfNecessary()
            // element visibility
            stopButton.alpha = sliderTrackingProgress > 0 ? 1 : 0
            slidingCircleView.alpha = sliderTrackingProgress > 0 ? 1 : 0
            lockIconView.alpha = 1
            lockIconView.setState(sliderTrackingProgress > 0.5 ? .locking : .unlocked, animated: true)
            shutterButtonInnerCircle.backgroundColor = .ows_white
            // element sizes
            outerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonRecordingSize
            // Inner (white) circle gets smaller as user drags the slider and reveals stop button when the slider is halfway to the lock icon.
            innerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonDefaultSize - 2 * sliderTrackingProgress * (CameraCaptureControl.shutterButtonDefaultSize - CameraCaptureControl.recordingLockControlSize)

        case .recordingLocked:
            prepareRecordingControlsIfNecessary()
            // element visibility
            stopButton.alpha = 1
            slidingCircleView.alpha = 1
            lockIconView.alpha = 1
            lockIconView.setState(.locked, animated: true)
            shutterButtonInnerCircle.alpha = 0
            shutterButtonInnerCircle.backgroundColor = .ows_white
            // element sizes
            outerCircleSizeConstraint.constant = CameraCaptureControl.shutterButtonRecordingSize
            innerCircleSizeConstraint.constant = CameraCaptureControl.recordingLockControlSize
        }

        setNeedsLayout()
        layoutIfNeeded()
    }

    private func prepareRecordingControlsIfNecessary() {
        guard slidingCirclePositionContstraint == nil else { return }

        addSubview(stopButton)
        stopButton.autoPin(toAspectRatio: 1)
        stopButton.autoSetDimension(.width, toSize: CameraCaptureControl.recordingLockControlSize)
        stopButton.centerXAnchor.constraint(equalTo: shutterButtonOuterCircle.centerXAnchor).isActive = true
        stopButton.centerYAnchor.constraint(equalTo: shutterButtonOuterCircle.centerYAnchor).isActive = true

        insertSubview(slidingCircleView, belowSubview: shutterButtonInnerCircle)
        slidingCircleView.autoVCenterInSuperview()
        slidingCirclePositionContstraint = slidingCircleView.centerXAnchor.constraint(equalTo: shutterButtonOuterCircle.centerXAnchor, constant: 0)
        addConstraint(slidingCirclePositionContstraint)

        addSubview(lockIconView)
        lockIconView.autoVCenterInSuperview()
        lockIconView.autoPinTrailing(toEdgeOf: self)

        setNeedsLayout()
        UIView.performWithoutAnimation {
            self.layoutIfNeeded()
        }
    }

    // MARK: - Gestures

    private var longPressGesture: UILongPressGestureRecognizer!
    private static let longPressDurationThreshold = 0.5
    private var initialTouchLocation: CGPoint?
    private var touchTimer: Timer?

    @objc
    private func handleLongPress(gesture: UILongPressGestureRecognizer) {
        guard let gestureView = gesture.view else {
            owsFailDebug("gestureView was unexpectedly nil")
            return
        }

        switch gesture.state {
        case .possible:
            break

        case .began:
            guard state == .initial else { break }

            initialTouchLocation = gesture.location(in: gesture.view)

            touchTimer?.invalidate()
            touchTimer = WeakTimer.scheduledTimer(
                timeInterval: CameraCaptureControl.longPressDurationThreshold,
                target: self,
                userInfo: nil,
                repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }

                self.setState(.recording, animationDuration: 0.4)
                
                self.delegate?.cameraCaptureControlDidRequestStartVideoRecording(self)
            }

        case .changed:
            guard state == .recording else { break }

            guard let referenceHeight = delegate?.zoomScaleReferenceHeight else {
                owsFailDebug("referenceHeight was unexpectedly nil")
                return
            }

            guard referenceHeight > 0 else {
                owsFailDebug("referenceHeight was unexpectedly <= 0")
                return
            }

            guard let initialTouchLocation = initialTouchLocation else {
                owsFailDebug("initialTouchLocation was unexpectedly nil")
                return
            }

            let currentLocation = gesture.location(in: gestureView)

            // Zoom
            let minDistanceBeforeActivatingZoom: CGFloat = 30
            let yDistance = initialTouchLocation.y - currentLocation.y - minDistanceBeforeActivatingZoom
            let distanceForFullZoom = referenceHeight / 4
            let yRatio = yDistance / distanceForFullZoom
            let yAlpha = yRatio.clamp(0, 1)
            delegate?.cameraCaptureControl(self, didUpdate: yAlpha)

            // Video Recording Lock
            let xOffset = currentLocation.x - initialTouchLocation.x
            updateTracking(xOffset: xOffset)

        case .ended:
            touchTimer?.invalidate()
            touchTimer = nil

            guard state != .recordingLocked else { return }

            if state == .recording {
                setState(.initial, animationDuration: 0.2)

                delegate?.cameraCaptureControlDidRequestFinishVideoRecording(self)
            } else {
                delegate?.cameraCaptureControlDidRequestCapturePhoto(self)
            }

        case .cancelled, .failed:
            if state == .recording {
                setState(.initial, animationDuration: 0.2)

                delegate?.cameraCaptureControlDidRequestCancelVideoRecording(self)
            }

            touchTimer?.invalidate()
            touchTimer = nil

        @unknown default:
            owsFailDebug("unexpected gesture state: \(gesture.state.rawValue)")
        }
    }

    private func updateTracking(xOffset: CGFloat) {
        let minDistanceBeforeActivatingLockSlider: CGFloat = 30
        let effectiveDistance = xOffset - minDistanceBeforeActivatingLockSlider
        let distanceToLock = abs(lockIconView.center.x - stopButton.center.x)
        let trackingPosition = effectiveDistance.clamp(0, distanceToLock)
        slidingCirclePositionContstraint.constant = trackingPosition
        sliderTrackingProgress = (effectiveDistance / distanceToLock).clamp(0, 1)

        Logger.verbose("xOffset: \(xOffset), effectiveDistance: \(effectiveDistance),  distanceToLock: \(distanceToLock), trackingPosition: \(trackingPosition), progress: \(sliderTrackingProgress)")
    }

    // MARK: - Button Actions

    private func didTapStopButton() {
        delegate?.cameraCaptureControlDidRequestFinishVideoRecording(self)
    }

    // MARK: - LockView

    private class LockView: UIView {

        private var imageViewLock = UIImageView(image: UIImage(named: "media-composer-lock-outline-24"))
        private var blurBackgroundView = CircleBlurView(effect: UIBlurEffect(style: .dark))
        private var whiteBackgroundView = CircleView()
        private var whiteCircleView = CircleView()

        enum State {
            case unlocked
            case locking
            case locked
        }
        private var _internalState: State = .unlocked
        var state: State {
            set {
                guard _internalState != newValue else { return }
                setState(newValue)
            }
            get {
                _internalState
            }
        }

        func setState(_ state: State, animated: Bool = false) {
            _internalState = state
            if animated {
                UIView.animate(withDuration: 0.25,
                               delay: 0,
                               options: [ .beginFromCurrentState ]) {
                    self.updateAppearance()
                }
            } else {
                updateAppearance()
            }
        }

        private func updateAppearance() {
            switch state {
            case .unlocked:
                blurBackgroundView.alpha = 1
                whiteCircleView.alpha = 0
                whiteBackgroundView.alpha = 0
                imageViewLock.alpha = 1
                imageViewLock.tintColor = .ows_white

            case .locking:
                blurBackgroundView.alpha = 1
                whiteCircleView.alpha = 1
                whiteBackgroundView.alpha = 0
                imageViewLock.alpha = 0

            case .locked:
                blurBackgroundView.alpha = 0
                whiteCircleView.alpha = 0
                whiteBackgroundView.alpha = 1
                imageViewLock.alpha = 1
                imageViewLock.tintColor = .ows_black
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            commonInit()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            commonInit()
        }

        private func commonInit() {
            isUserInteractionEnabled = false

            addSubview(blurBackgroundView)
            blurBackgroundView.autoPinEdgesToSuperviewEdges()

            addSubview(whiteCircleView)
            whiteCircleView.backgroundColor = .clear
            whiteCircleView.layer.borderColor = UIColor.ows_white.cgColor
            whiteCircleView.layer.borderWidth = 3
            whiteCircleView.autoPinEdgesToSuperviewEdges()

            addSubview(whiteBackgroundView)
            whiteBackgroundView.backgroundColor = .ows_white
            whiteBackgroundView.autoPinEdgesToSuperviewEdges()

            addSubview(imageViewLock)
            imageViewLock.tintColor = .ows_white
            imageViewLock.autoCenterInSuperview()

            updateAppearance()
        }

        override var intrinsicContentSize: CGSize {
            CGSize(width: CameraCaptureControl.recordingLockControlSize, height: CameraCaptureControl.recordingLockControlSize)
        }
    }
}
