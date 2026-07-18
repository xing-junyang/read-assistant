import UIKit
import AVFoundation

// MARK: - PlaybackBarViewDelegate
protocol PlaybackBarViewDelegate: AnyObject {
    func playbackBarViewDidFinishPlaying(_ view: PlaybackBarView)
    func playbackBarView(_ view: PlaybackBarView, didEncounterError error: Error)
}

// MARK: - PlaybackBarView
/// A self-contained audio playback bar with play/pause, progress slider, and duration labels.
/// Designed for iOS 10+ compatibility using only UIKit components.
final class PlaybackBarView: UIView {

    // MARK: - Constants
    private enum Metrics {
        static let barHeight: CGFloat = 64
        static let buttonSize: CGFloat = 44
        static let horizontalPadding: CGFloat = 12
        static let labelWidth: CGFloat = 48
        static let spacing: CGFloat = 8
    }

    // MARK: - Properties
    weak var delegate: PlaybackBarViewDelegate?

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private var isUserSeeking = false

    /// The audio file URL currently loaded (nil if no audio).
    private(set) var audioURL: URL?

    /// Whether audio is currently playing.
    var isPlaying: Bool {
        return audioPlayer?.isPlaying ?? false
    }

    // MARK: - Subviews
    private let containerView = UIView()
    private let playPauseButton = UIButton(type: .system)
    private let progressSlider = UISlider()
    private let currentTimeLabel = UILabel()
    private let totalTimeLabel = UILabel()
    private let titleLabel = UILabel()

    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    deinit {
        stopPlayback()
        progressTimer?.invalidate()
    }

    // MARK: - UI Setup
    private func setupUI() {
        backgroundColor = .cardBackground
        layer.cornerRadius = 10
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowOffset = CGSize(width: 0, height: -2)
        layer.shadowRadius = 4

        // Container
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        // Title label
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .textSecondary
        titleLabel.text = "录音回放"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        // Play/Pause button
        playPauseButton.setTitle("▶", for: .normal)
        playPauseButton.titleLabel?.font = UIFont.systemFont(ofSize: 24)
        playPauseButton.setTitleColor(.primary, for: .normal)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(playPauseButton)

        // Current time label
        currentTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        currentTimeLabel.textColor = .textSecondary
        currentTimeLabel.text = "00:00"
        currentTimeLabel.textAlignment = .center
        currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(currentTimeLabel)

        // Progress slider
        progressSlider.minimumTrackTintColor = .primary
        progressSlider.maximumTrackTintColor = .separator
        progressSlider.setThumbImage(makeThumbImage(size: 14), for: .normal)
        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.value = 0
        progressSlider.isContinuous = true
        progressSlider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside])
        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(progressSlider)

        // Total time label
        totalTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        totalTimeLabel.textColor = .textSecondary
        totalTimeLabel.text = "00:00"
        totalTimeLabel.textAlignment = .center
        totalTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(totalTimeLabel)

        // Layout constraints
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalPadding),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalPadding),

            // Title (top row)
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: 16),

            // Play/Pause button (left)
            playPauseButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: progressSlider.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: Metrics.buttonSize),
            playPauseButton.heightAnchor.constraint(equalToConstant: Metrics.buttonSize),

            // Current time label
            currentTimeLabel.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: Metrics.spacing),
            currentTimeLabel.centerYAnchor.constraint(equalTo: progressSlider.centerYAnchor),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: Metrics.labelWidth),

            // Progress slider (center)
            progressSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 4),
            progressSlider.trailingAnchor.constraint(equalTo: totalTimeLabel.leadingAnchor, constant: -4),
            progressSlider.centerYAnchor.constraint(equalTo: containerView.centerYAnchor, constant: 8),

            // Total time label
            totalTimeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            totalTimeLabel.centerYAnchor.constraint(equalTo: progressSlider.centerYAnchor),
            totalTimeLabel.widthAnchor.constraint(equalToConstant: Metrics.labelWidth)
        ])
    }

    // MARK: - Public API

    /// Loads an audio file and prepares for playback.
    /// - Parameter url: The URL of the audio file to play.
    func loadAudio(url: URL) throws {
        stopPlayback()

        // Configure audio session for playback
        try AudioSessionManager.shared.configureForPlayback()

        audioURL = url
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.delegate = self
        audioPlayer?.prepareToPlay()

        // Update total duration
        if let duration = audioPlayer?.duration, duration > 0 {
            totalTimeLabel.text = formatTime(duration)
            progressSlider.maximumValue = Float(duration)
            progressSlider.value = 0
        } else {
            totalTimeLabel.text = "00:00"
        }

        currentTimeLabel.text = "00:00"
        playPauseButton.setTitle("▶", for: .normal)
    }

    /// Starts or resumes playback.
    func play() {
        guard let player = audioPlayer, !player.isPlaying else { return }
        player.play()
        playPauseButton.setTitle("⏸", for: .normal)
        startProgressTimer()
    }

    /// Pauses playback.
    func pause() {
        guard let player = audioPlayer, player.isPlaying else { return }
        player.pause()
        playPauseButton.setTitle("▶", for: .normal)
        stopProgressTimer()
    }

    /// Stops playback and resets position.
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        audioURL = nil
        playPauseButton.setTitle("▶", for: .normal)
        progressSlider.value = 0
        currentTimeLabel.text = "00:00"
        totalTimeLabel.text = "00:00"
        stopProgressTimer()
        try? AudioSessionManager.shared.deactivate()
    }

    // MARK: - Actions

    @objc private func playPauseTapped() {
        if isPlaying {
            pause()
        } else if audioPlayer != nil {
            // If playback finished (player is at end), restart from beginning
            if audioPlayer?.currentTime ?? 0 >= (audioPlayer?.duration ?? 0) - 0.1 {
                audioPlayer?.currentTime = 0
                progressSlider.value = 0
                currentTimeLabel.text = "00:00"
            }
            play()
        }
    }

    @objc private func sliderTouchDown() {
        isUserSeeking = true
        stopProgressTimer()
    }

    @objc private func sliderValueChanged() {
        let time = TimeInterval(progressSlider.value)
        currentTimeLabel.text = formatTime(time)
    }

    @objc private func sliderTouchUp() {
        let time = TimeInterval(progressSlider.value)
        audioPlayer?.currentTime = time
        isUserSeeking = false

        if isPlaying {
            startProgressTimer()
        }
    }

    // MARK: - Timer

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let player = audioPlayer, !isUserSeeking else { return }
        let currentTime = player.currentTime
        progressSlider.value = Float(currentTime)
        currentTimeLabel.text = formatTime(currentTime)

        // Also update total time in case it wasn't available at load time
        if player.duration > 0 && totalTimeLabel.text == "00:00" {
            totalTimeLabel.text = formatTime(player.duration)
            progressSlider.maximumValue = Float(player.duration)
        }
    }

    // MARK: - Helpers

    /// Formats a time interval into "mm:ss" format.
    private func formatTime(_ interval: TimeInterval) -> String {
        guard interval >= 0 && interval.isFinite else { return "00:00" }
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Creates a simple circular thumb image for the slider.
    private func makeThumbImage(size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            UIColor.primary.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
    }
}

// MARK: - AVAudioPlayerDelegate
extension PlaybackBarView: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopProgressTimer()
            self.progressSlider.value = self.progressSlider.maximumValue
            self.currentTimeLabel.text = self.formatTime(player.duration)
            self.playPauseButton.setTitle("▶", for: .normal)
            self.delegate?.playbackBarViewDidFinishPlaying(self)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error = error {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.playbackBarView(self, didEncounterError: error)
            }
        }
    }
}
