import UIKit
import SceneKit

// MARK: - Battlefield Game View Controller
/// Minecraft-style 3D battlefield shooting game using SceneKit (iOS 10+).
/// Landscape-only, play against bots. Costs 20 coins per play.
final class BattlefieldGameViewController: UIViewController {

    // MARK: - Game State
    private var hp: Int = 100
    private let maxHp: Int = 100
    private var ammo: Int = 30
    private let maxAmmo: Int = 30
    private var kills: Int = 0
    private let totalBots: Int = 8
    private var score: Int = 0
    private var isGameOver: Bool = false
    private var isReloading: Bool = false
    private var shootCooldown: TimeInterval = 0
    private var isShooting: Bool = false

    // MARK: - SceneKit
    private let scnView = SCNView()
    private let scene = SCNScene()
    private let cameraHolder = SCNNode()
    private let cameraNode = SCNNode()
    private let weaponNode = SCNNode()
    private var terrainNodes: [SCNNode] = []

    // Bots
    private struct Bot {
        let node: SCNNode
        var hp: Int
        var alive: Bool
        var shootTimer: TimeInterval
        var strafeDir: Float
        var strafeTimer: TimeInterval
    }
    private var bots: [Bot] = []

    // Bullets
    private struct Bullet {
        let node: SCNNode
        var velocity: SCNVector3
        var lifetime: TimeInterval
        var isBotBullet: Bool
    }
    private var bullets: [Bullet] = []
    private var particleNodes: [SCNNode] = []

    // MARK: - Controls
    private var joystickActive = false
    private var moveInput = CGPoint.zero

    // HUD views
    private let healthFill = UIView()
    private let healthLabel = UILabel()
    private let ammoLabel = UILabel()
    private let killsLabel = UILabel()
    private let scoreLabel = UILabel()
    private let crosshairView = UIImageView()
    private let messageLabel = UILabel()

    // Joystick
    private let joystickBase = UIView()
    private let joystickKnob = UIView()

    // Buttons
    private let shootButton = UIButton(type: .custom)
    private let reloadButton = UIButton(type: .custom)

    // Game Over
    private let gameOverView = UIView()

    // Map — flat ground with barriers as cover
    private let mapSize = 56
    private let groundY: Float = 0.0       // ground block center
    private let groundTop: Float = 0.5      // top surface of ground blocks
    private let playerY: Float = 1.5        // camera eye height
    private let botFootY: Float = 0.5       // bot base position

    // Barrier collision boxes
    private struct BBox {
        let minX: Float; let maxX: Float
        let minZ: Float; let maxZ: Float
        let minY: Float; let maxY: Float
    }
    private var barrierBoxes: [BBox] = []

    // Timer
    private var gameTimer: Timer?
    private var lastTime: TimeInterval = 0

    // MARK: - Init
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildScene()
        buildHUD()
        buildJoystick()
        buildButtons()
        buildGameOver()
        generateTerrain()
        spawnPlayer()
        spawnBots()
        lastTime = CACurrentMediaTime()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        forceLandscape()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        gameTimer?.invalidate()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var shouldAutorotate: Bool { true }

    private func forceLandscape() {
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
    }

    // MARK: - SceneKit Build
    private func buildScene() {
        scnView.scene = scene
        scnView.backgroundColor = UIColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1)
        scnView.antialiasingMode = .multisampling2X
        scnView.allowsCameraControl = false
        scnView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scnView)
        NSLayoutConstraint.activate([
            scnView.topAnchor.constraint(equalTo: view.topAnchor),
            scnView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scnView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scnView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Camera
        cameraHolder.position = SCNVector3(0, 1.6, 0)
        scene.rootNode.addChildNode(cameraHolder)
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 200
        cameraNode.camera?.xFov = 55
        cameraNode.camera?.yFov = 55
        cameraHolder.addChildNode(cameraNode)

        // Weapon model
        let bodyGeo = SCNBox(width: 0.06, height: 0.1, length: 0.35, chamferRadius: 0.01)
        bodyGeo.firstMaterial?.diffuse.contents = UIColor.darkGray
        let bodyNode = SCNNode(geometry: bodyGeo)
        bodyNode.position = SCNVector3(0.15, -0.12, -0.3)
        weaponNode.addChildNode(bodyNode)

        let barrelGeo = SCNBox(width: 0.035, height: 0.035, length: 0.25, chamferRadius: 0.005)
        barrelGeo.firstMaterial?.diffuse.contents = UIColor.gray
        let barrel = SCNNode(geometry: barrelGeo)
        barrel.position = SCNVector3(0.15, -0.1, -0.55)
        weaponNode.addChildNode(barrel)

        cameraNode.addChildNode(weaponNode)

        // Lighting
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.55, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 1)
        sun.position = SCNVector3(20, 35, 15)
        sun.constraints = [SCNLookAtConstraint(target: scene.rootNode)]
        scene.rootNode.addChildNode(sun)

        scene.fogColor = UIColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1)
        scene.fogStartDistance = 40
        scene.fogEndDistance = 90
    }

    // MARK: - HUD
    private func buildHUD() {
        let bar = UIStackView()
        bar.axis = .horizontal
        bar.spacing = 8
        bar.alignment = .center
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isUserInteractionEnabled = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor, constant: 4),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.heightAnchor.constraint(equalToConstant: 28)
        ])

        // Health
        let healthBg = UIView()
        healthBg.backgroundColor = UIColor(white: 0, alpha: 0.5)
        healthBg.layer.cornerRadius = 6
        healthBg.layer.borderWidth = 1.5
        healthBg.layer.borderColor = UIColor(white: 0.5, alpha: 0.6).cgColor
        healthBg.translatesAutoresizingMaskIntoConstraints = false
        healthBg.widthAnchor.constraint(equalToConstant: 170).isActive = true
        healthBg.heightAnchor.constraint(equalToConstant: 24).isActive = true

        healthFill.backgroundColor = UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
        healthFill.layer.cornerRadius = 5
        healthFill.translatesAutoresizingMaskIntoConstraints = false
        healthBg.addSubview(healthFill)
        NSLayoutConstraint.activate([
            healthFill.leadingAnchor.constraint(equalTo: healthBg.leadingAnchor, constant: 2),
            healthFill.centerYAnchor.constraint(equalTo: healthBg.centerYAnchor),
            healthFill.widthAnchor.constraint(equalToConstant: 166),
            healthFill.heightAnchor.constraint(equalToConstant: 20)
        ])

        healthLabel.text = "❤️ 100"
        healthLabel.textColor = .white
        healthLabel.font = .boldSystemFont(ofSize: 12)
        healthLabel.textAlignment = .center
        healthLabel.translatesAutoresizingMaskIntoConstraints = false
        healthBg.addSubview(healthLabel)
        healthLabel.centerXAnchor.constraint(equalTo: healthBg.centerXAnchor).isActive = true
        healthLabel.centerYAnchor.constraint(equalTo: healthBg.centerYAnchor).isActive = true
        bar.addArrangedSubview(healthBg)

        // Ammo
        ammoLabel.text = "🔫 30"
        ammoLabel.textColor = .white
        ammoLabel.font = .boldSystemFont(ofSize: 14)
        ammoLabel.backgroundColor = UIColor(white: 0, alpha: 0.5)
        ammoLabel.layer.cornerRadius = 6
        ammoLabel.layer.borderWidth = 1.5
        ammoLabel.layer.borderColor = UIColor(white: 0.5, alpha: 0.6).cgColor
        ammoLabel.clipsToBounds = true
        ammoLabel.textAlignment = .center
        ammoLabel.widthAnchor.constraint(equalToConstant: 62).isActive = true
        ammoLabel.heightAnchor.constraint(equalToConstant: 28).isActive = true
        bar.addArrangedSubview(ammoLabel)

        // Kills
        killsLabel.text = "💀 0/8"
        killsLabel.textColor = .white
        killsLabel.font = .boldSystemFont(ofSize: 14)
        killsLabel.backgroundColor = UIColor(white: 0, alpha: 0.5)
        killsLabel.layer.cornerRadius = 6
        killsLabel.layer.borderWidth = 1.5
        killsLabel.layer.borderColor = UIColor(white: 0.5, alpha: 0.6).cgColor
        killsLabel.clipsToBounds = true
        killsLabel.textAlignment = .center
        killsLabel.widthAnchor.constraint(equalToConstant: 68).isActive = true
        killsLabel.heightAnchor.constraint(equalToConstant: 28).isActive = true
        bar.addArrangedSubview(killsLabel)

        // Score
        scoreLabel.text = "⭐ 0"
        scoreLabel.textColor = UIColor(red: 1, green: 0.85, blue: 0, alpha: 1)
        scoreLabel.font = .boldSystemFont(ofSize: 14)
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scoreLabel)
        NSLayoutConstraint.activate([
            scoreLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scoreLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])

        // Crosshair
        crosshairView.image = drawCrosshairImage()
        crosshairView.contentMode = .center
        crosshairView.isUserInteractionEnabled = false
        crosshairView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(crosshairView)
        NSLayoutConstraint.activate([
            crosshairView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            crosshairView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            crosshairView.widthAnchor.constraint(equalToConstant: 36),
            crosshairView.heightAnchor.constraint(equalToConstant: 36)
        ])

        // Message
        messageLabel.textColor = UIColor(red: 1, green: 0.85, blue: 0, alpha: 1)
        messageLabel.font = .boldSystemFont(ofSize: 24)
        messageLabel.textAlignment = .center
        messageLabel.isUserInteractionEnabled = false
        messageLabel.alpha = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageLabel)
        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50)
        ])
    }

    private func drawCrosshairImage() -> UIImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 36))
        return r.image { ctx in
            UIColor.white.withAlphaComponent(0.65).setStroke()
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 18, y: 2)); p.addLine(to: CGPoint(x: 18, y: 12))
            p.move(to: CGPoint(x: 18, y: 24)); p.addLine(to: CGPoint(x: 18, y: 34))
            p.move(to: CGPoint(x: 2, y: 18)); p.addLine(to: CGPoint(x: 12, y: 18))
            p.move(to: CGPoint(x: 24, y: 18)); p.addLine(to: CGPoint(x: 34, y: 18))
            p.lineWidth = 2; p.stroke()
        }
    }

    // MARK: - Joystick
    private func buildJoystick() {
        let size: CGFloat = 140
        joystickBase.frame = CGRect(x: 0, y: 0, width: size, height: size)
        joystickBase.backgroundColor = UIColor(white: 1, alpha: 0.08)
        joystickBase.layer.cornerRadius = size / 2
        joystickBase.layer.borderWidth = 2
        joystickBase.layer.borderColor = UIColor(white: 1, alpha: 0.25).cgColor
        joystickBase.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(joystickBase)
        NSLayoutConstraint.activate([
            joystickBase.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            joystickBase.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50),
            joystickBase.widthAnchor.constraint(equalToConstant: size),
            joystickBase.heightAnchor.constraint(equalToConstant: size)
        ])

        let kSize: CGFloat = 58
        joystickKnob.frame = CGRect(x: (size - kSize) / 2, y: (size - kSize) / 2, width: kSize, height: kSize)
        joystickKnob.backgroundColor = UIColor(white: 1, alpha: 0.35)
        joystickKnob.layer.cornerRadius = kSize / 2
        joystickKnob.layer.borderWidth = 2
        joystickKnob.layer.borderColor = UIColor(white: 1, alpha: 0.5).cgColor
        joystickBase.addSubview(joystickKnob)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onJoystickPan))
        joystickBase.addGestureRecognizer(pan)

        // Camera rotation via drag on blank canvas area
        let lookPan = UIPanGestureRecognizer(target: self, action: #selector(onLookPan))
        lookPan.maximumNumberOfTouches = 1
        scnView.addGestureRecognizer(lookPan)
    }

    @objc private func onJoystickPan(_ g: UIPanGestureRecognizer) {
        let c = CGPoint(x: joystickBase.bounds.midX, y: joystickBase.bounds.midY)
        let mr: CGFloat = 40
        switch g.state {
        case .began, .changed:
            let loc = g.location(in: joystickBase)
            var dx = loc.x - c.x; var dy = loc.y - c.y
            let d = sqrt(dx * dx + dy * dy)
            if d > mr { dx = dx / d * mr; dy = dy / d * mr }
            joystickKnob.center = CGPoint(x: c.x + dx, y: c.y + dy)
            joystickActive = d > 8
            moveInput = joystickActive ? CGPoint(x: -dx / mr, y: -dy / mr) : .zero
        case .ended, .cancelled:
            joystickActive = false; moveInput = .zero
            UIView.animate(withDuration: 0.15) { self.joystickKnob.center = c }
        default: break
        }
    }

    @objc private func onLookPan(_ g: UIPanGestureRecognizer) {
        guard !isGameOver else { return }
        let translation = g.translation(in: scnView)
        let sensitivity: Float = 0.003
        cameraNode.eulerAngles.y -= Float(translation.x) * sensitivity
        cameraNode.eulerAngles.x -= Float(translation.y) * sensitivity
        // Clamp pitch
        cameraNode.eulerAngles.x = max(-Float.pi / 3, min(Float.pi / 3, cameraNode.eulerAngles.x))
        g.setTranslation(.zero, in: scnView)
    }

    // MARK: - Buttons
    private func buildButtons() {
        shootButton.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        shootButton.backgroundColor = UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.35)
        shootButton.layer.cornerRadius = 40
        shootButton.layer.borderWidth = 2.5
        shootButton.layer.borderColor = UIColor(red: 1, green: 0.4, blue: 0.4, alpha: 0.6).cgColor
        shootButton.setTitle("💥", for: .normal)
        shootButton.titleLabel?.font = .systemFont(ofSize: 30)
        shootButton.translatesAutoresizingMaskIntoConstraints = false
        shootButton.addTarget(self, action: #selector(shootTapDown), for: .touchDown)
        shootButton.addTarget(self, action: #selector(shootTapUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        view.addSubview(shootButton)
        NSLayoutConstraint.activate([
            shootButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            shootButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -60),
            shootButton.widthAnchor.constraint(equalToConstant: 80),
            shootButton.heightAnchor.constraint(equalToConstant: 80)
        ])

        reloadButton.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        reloadButton.backgroundColor = UIColor(red: 1, green: 0.75, blue: 0.1, alpha: 0.25)
        reloadButton.layer.cornerRadius = 25
        reloadButton.layer.borderWidth = 2
        reloadButton.layer.borderColor = UIColor(red: 1, green: 0.75, blue: 0.1, alpha: 0.5).cgColor
        reloadButton.setTitle("🔄", for: .normal)
        reloadButton.titleLabel?.font = .systemFont(ofSize: 20)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.addTarget(self, action: #selector(reloadTap), for: .touchUpInside)
        view.addSubview(reloadButton)
        NSLayoutConstraint.activate([
            reloadButton.trailingAnchor.constraint(equalTo: shootButton.leadingAnchor, constant: -16),
            reloadButton.bottomAnchor.constraint(equalTo: shootButton.centerYAnchor, constant: -8),
            reloadButton.widthAnchor.constraint(equalToConstant: 50),
            reloadButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc private func shootTapDown() { isShooting = true; tryShoot() }
    @objc private func shootTapUp() { isShooting = false }
    @objc private func reloadTap() { reload() }

    // MARK: - Game Over
    private func buildGameOver() {
        gameOverView.backgroundColor = UIColor(white: 0, alpha: 0.85)
        gameOverView.alpha = 0
        gameOverView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gameOverView)
        NSLayoutConstraint.activate([
            gameOverView.topAnchor.constraint(equalTo: view.topAnchor),
            gameOverView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gameOverView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gameOverView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let title = UILabel(); title.tag = 100
        title.textColor = .white; title.font = .boldSystemFont(ofSize: 42); title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        gameOverView.addSubview(title)

        let stats = UILabel(); stats.tag = 101
        stats.textColor = UIColor(white: 0.8, alpha: 1); stats.font = .systemFont(ofSize: 20)
        stats.textAlignment = .center; stats.numberOfLines = 0
        stats.translatesAutoresizingMaskIntoConstraints = false
        gameOverView.addSubview(stats)

        let retry = UIButton(type: .system)
        retry.setTitle("再来一局 (-20💰)", for: .normal)
        retry.titleLabel?.font = .boldSystemFont(ofSize: 20)
        retry.setTitleColor(.white, for: .normal)
        retry.backgroundColor = UIColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1)
        retry.layer.cornerRadius = 12
        retry.translatesAutoresizingMaskIntoConstraints = false
        retry.addTarget(self, action: #selector(retryTap), for: .touchUpInside)
        gameOverView.addSubview(retry)

        let exit = UIButton(type: .system)
        exit.setTitle("退出", for: .normal)
        exit.titleLabel?.font = .boldSystemFont(ofSize: 18)
        exit.setTitleColor(UIColor(white: 0.8, alpha: 1), for: .normal)
        exit.backgroundColor = UIColor(white: 0.3, alpha: 1)
        exit.layer.cornerRadius = 12
        exit.translatesAutoresizingMaskIntoConstraints = false
        exit.addTarget(self, action: #selector(exitTap), for: .touchUpInside)
        gameOverView.addSubview(exit)

        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            title.bottomAnchor.constraint(equalTo: gameOverView.centerYAnchor, constant: -30),
            stats.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            stats.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
            retry.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            retry.topAnchor.constraint(equalTo: stats.bottomAnchor, constant: 30),
            retry.widthAnchor.constraint(equalToConstant: 220), retry.heightAnchor.constraint(equalToConstant: 50),
            exit.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            exit.topAnchor.constraint(equalTo: retry.bottomAnchor, constant: 12),
            exit.widthAnchor.constraint(equalToConstant: 220), exit.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func endGame(won: Bool) {
        isGameOver = true; isShooting = false
        (gameOverView.viewWithTag(100) as? UILabel)?.text = won ? "🏆 胜利!" : "💀 阵亡!"
        (gameOverView.viewWithTag(100) as? UILabel)?.textColor = won ?
            UIColor(red: 0.3, green: 0.85, blue: 0.3, alpha: 1) :
            UIColor(red: 0.95, green: 0.2, blue: 0.2, alpha: 1)
        (gameOverView.viewWithTag(101) as? UILabel)?.text = "击杀: \(kills)/\(totalBots)\n剩余生命: \(hp)\n得分: \(score)"
        UIView.animate(withDuration: 0.4) { self.gameOverView.alpha = 1 }
    }

    @objc private func retryTap() {
        guard RewardManager.shared.spendCoins(DeveloperSettingsManager.shared.effectiveBattlefieldCostCoins) else {
            let a = UIAlertController(title: "金币不足", message: "金币不够了，请先完成阅读获取金币。", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "返回", style: .default) { [weak self] _ in self?.dismiss(animated: true) })
            present(a, animated: true); return
        }
        resetAll()
        UIView.animate(withDuration: 0.3) { self.gameOverView.alpha = 0 }
    }

    @objc private func exitTap() { dismiss(animated: true) }

    private func resetAll() {
        hp = maxHp; ammo = maxAmmo; kills = 0; score = 0
        isGameOver = false; isReloading = false; shootCooldown = 0; isShooting = false
        for b in bots { b.node.removeFromParentNode() }; bots.removeAll()
        for b in bullets { b.node.removeFromParentNode() }; bullets.removeAll()
        for p in particleNodes { p.removeFromParentNode() }; particleNodes.removeAll()
        spawnPlayer(); spawnBots(); refreshHUD()
    }

    // MARK: - Terrain (Super-Flat + Barriers)
    private func generateTerrain() {
        // Flat ground: one layer of grass-topped blocks across the entire map
        for x in stride(from: -mapSize/2, to: mapSize/2, by: 1) {
            for z in stride(from: -mapSize/2, to: mapSize/2, by: 1) {
                let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.02)
                box.firstMaterial?.diffuse.contents = UIColor(red: 0.49, green: 0.78, blue: 0.31, alpha: 1)
                box.firstMaterial?.specular.contents = UIColor(white: 0.05, alpha: 1)
                let n = SCNNode(geometry: box)
                n.position = SCNVector3(Float(x), groundY, Float(z))
                scene.rootNode.addChildNode(n)
                terrainNodes.append(n)
            }
        }

        // Barriers: walls and crates for cover — none within 4 blocks of origin
        let barriers: [(Float, Float, Int, Int, Int)] = [
            (-12, -10, 4, 1, 2), (12, -10, 1, 4, 2), (-8, -6, 1, 3, 2),
            (10, -6, 3, 1, 2), (-14, 0, 5, 1, 2), (14, -2, 1, 5, 2),
            (-4, -14, 3, 1, 2), (4, -14, 1, 3, 2), (0, -8, 4, 1, 2),
            (-10, 6, 1, 4, 2), (10, 4, 4, 1, 2), (-6, 12, 5, 1, 2),
            (6, 12, 1, 5, 2), (-16, 10, 3, 1, 2), (16, 10, 1, 3, 2),
            (0, 12, 6, 1, 2), (-12, 0, 2, 2, 2), (12, 8, 2, 2, 2),
            (-6, -2, 1, 3, 3), (6, -2, 1, 3, 2),
            (-18, -15, 1, 2, 2), (18, -15, 1, 2, 2), (-18, 15, 1, 2, 2), (18, 15, 1, 2, 2),
        ]

        for (cx, cz, bw, bd, bh) in barriers {
            let hw = Float(bw) / 2, hd = Float(bd) / 2
            let minX = cx - hw, maxX = cx + hw
            let minZ = cz - hd, maxZ = cz + hd
            barrierBoxes.append(BBox(minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ, minY: groundTop, maxY: groundTop + Float(bh)))

            // Place blocks
            let bxStart = Int(floor(minX + 0.5)), bxEnd = Int(floor(maxX + 0.5))
            let bzStart = Int(floor(minZ + 0.5)), bzEnd = Int(floor(maxZ + 0.5))
            for bx in bxStart...bxEnd {
                for bz in bzStart...bzEnd {
                    for by in 0..<bh {
                        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.02)
                        let isEdge = bx == bxStart || bx == bxEnd || bz == bzStart || bz == bzEnd
                        box.firstMaterial?.diffuse.contents = isEdge ?
                            UIColor(red: 0.55, green: 0.35, blue: 0.15, alpha: 1) :
                            UIColor(red: 0.6, green: 0.55, blue: 0.45, alpha: 1)
                        let n = SCNNode(geometry: box)
                        n.position = SCNVector3(Float(bx), groundTop + 0.5 + Float(by), Float(bz))
                        scene.rootNode.addChildNode(n)
                    }
                }
            }
        }
    }

    // MARK: - Player & Bots
    private func spawnPlayer() {
        cameraHolder.position = SCNVector3(0, playerY, 0)
        cameraNode.eulerAngles = SCNVector3(0, 0, 0)
    }

    private func spawnBots() {
        let colors: [UIColor] = [
            UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
            UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1),
            UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1),
            UIColor(red: 0.7, green: 0.4, blue: 0.1, alpha: 1),
            UIColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1),
            UIColor(red: 0.1, green: 0.6, blue: 0.7, alpha: 1),
            UIColor(red: 0.8, green: 0.5, blue: 0, alpha: 1),
            UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1),
        ]
        for i in 0..<totalBots {
            var bx: Int, bz: Int
            repeat {
                bx = Int.random(in: (-mapSize/2+3)...(mapSize/2-4))
                bz = Int.random(in: (-mapSize/2+3)...(mapSize/2-4))
            } while (abs(bx) < 5 && abs(bz) < 5)
                || isInsideBarrier(x: Float(bx), y: botFootY, z: Float(bz))
            let n = makeBot(colors[i])
            n.position = SCNVector3(Float(bx), botFootY, Float(bz))
            scene.rootNode.addChildNode(n)
            bots.append(Bot(node: n, hp: 50, alive: true, shootTimer: TimeInterval.random(in: 1...2.5), strafeDir: Bool.random() ? 1 : -1, strafeTimer: TimeInterval.random(in: 1...3)))
        }
    }

    private func makeBot(_ c: UIColor) -> SCNNode {
        let g = SCNNode()
        let body = SCNNode(geometry: { let b = SCNBox(width: 0.6, height: 0.8, length: 0.4, chamferRadius: 0.02); b.firstMaterial?.diffuse.contents = c; return b }())
        body.position.y = 0.9; g.addChildNode(body)

        let head = SCNNode(geometry: { let b = SCNBox(width: 0.45, height: 0.45, length: 0.45, chamferRadius: 0.02); b.firstMaterial?.diffuse.contents = c.withAlphaComponent(0.9); return b }())
        head.position.y = 1.55; g.addChildNode(head)

        let eye = SCNBox(width: 0.1, height: 0.1, length: 0.02, chamferRadius: 0); eye.firstMaterial?.diffuse.contents = UIColor.black
        let le = SCNNode(geometry: eye); le.position = SCNVector3(-0.1, 1.6, 0.23); g.addChildNode(le)
        let re = SCNNode(geometry: eye); re.position = SCNVector3(0.1, 1.6, 0.23); g.addChildNode(re)

        let leg = SCNBox(width: 0.18, height: 0.6, length: 0.18, chamferRadius: 0.01); leg.firstMaterial?.diffuse.contents = c.withAlphaComponent(0.7)
        let ll = SCNNode(geometry: leg); ll.position = SCNVector3(-0.15, 0.3, 0); g.addChildNode(ll)
        let rl = SCNNode(geometry: leg); rl.position = SCNVector3(0.15, 0.3, 0); g.addChildNode(rl)
        return g
    }

    // MARK: - Combat
    private func tryShoot() {
        guard !isGameOver, !isReloading, ammo > 0, shootCooldown <= 0 else { return }
        ammo -= 1; shootCooldown = 0.13; refreshHUD()
        let fwd = worldFront(of: cameraNode.presentation)
        let spawn = cameraHolder.presentation.convertPosition(SCNVector3(0.15, -0.1, -0.6), to: scene.rootNode)
        let b = SCNSphere(radius: 0.04)
        b.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.9, blue: 0.2, alpha: 1)
        let bn = SCNNode(geometry: b); bn.position = spawn; scene.rootNode.addChildNode(bn)
        bullets.append(Bullet(node: bn, velocity: SCNVector3(fwd.x*55, fwd.y*55, fwd.z*55), lifetime: 0, isBotBullet: false))
        particles(at: spawn, color: UIColor(red: 1, green: 0.9, blue: 0.2, alpha: 1), count: 3)
        weaponNode.position.z = -0.22
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.weaponNode.position.z = -0.3 }
    }

    private func botFire(_ bot: Bot) {
        let bp = bot.node.presentation.position
        let head = SCNVector3(bp.x, bp.y + 1.5, bp.z)
        let to = SCNVector3(cameraHolder.presentation.position.x - head.x, cameraHolder.presentation.position.y - head.y, cameraHolder.presentation.position.z - head.z)
        let len = sqrt(to.x*to.x + to.y*to.y + to.z*to.z); guard len > 0 else { return }
        let d = SCNVector3(to.x/len, to.y/len, to.z/len)
        let b = SCNSphere(radius: 0.04)
        b.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.5, blue: 0.2, alpha: 1)
        let bn = SCNNode(geometry: b); bn.position = SCNVector3(head.x+d.x*0.4, head.y+d.y*0.4, head.z+d.z*0.4)
        scene.rootNode.addChildNode(bn)
        bullets.append(Bullet(node: bn, velocity: SCNVector3(d.x*30, d.y*30, d.z*30), lifetime: 0, isBotBullet: true))
    }

    private func reload() {
        guard !isReloading, ammo < maxAmmo, !isGameOver else { return }
        isReloading = true; showMsg("换弹中..."); refreshHUD()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let s = self else { return }; s.ammo = s.maxAmmo; s.isReloading = false; s.hideMsg(); s.refreshHUD()
        }
    }

    private func particles(at pos: SCNVector3, color: UIColor, count: Int) {
        for _ in 0..<count {
            let g = SCNBox(width: 0.04, height: 0.04, length: 0.04, chamferRadius: 0)
            g.firstMaterial?.diffuse.contents = color
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(pos.x + Float.random(in: -0.2...0.2), pos.y + Float.random(in: -0.1...0.3), pos.z + Float.random(in: -0.2...0.2))
            scene.rootNode.addChildNode(n); particleNodes.append(n)
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.6
            n.position = SCNVector3(n.position.x + Float.random(in: -1.5...1.5), n.position.y + Float.random(in: 1...4), n.position.z + Float.random(in: -1.5...1.5))
            n.opacity = 0
            SCNTransaction.completionBlock = { n.removeFromParentNode() }; SCNTransaction.commit()
        }
    }

    private func hurtPlayer(_ dmg: Int) {
        hp = max(0, hp - dmg); refreshHUD()
        UIView.animate(withDuration: 0.1, animations: { self.view.backgroundColor = UIColor(red: 0.3, green: 0, blue: 0, alpha: 1) }) { _ in
            UIView.animate(withDuration: 0.2) { self.view.backgroundColor = .black }
        }
        if hp <= 0 { endGame(won: false) }
    }

    // MARK: - HUD
    private func refreshHUD() {
        let r = CGFloat(hp) / CGFloat(maxHp)
        for c in healthFill.superview?.constraints ?? [] where c.firstItem === healthFill && c.firstAttribute == .width { c.constant = 166 * r; break }
        healthLabel.text = "❤️ \(hp)"
        ammoLabel.text = isReloading ? "🔄 ..." : "🔫 \(ammo)"
        killsLabel.text = "💀 \(kills)/\(totalBots)"
        scoreLabel.text = "⭐ \(score)"
    }

    private func showMsg(_ t: String) { messageLabel.text = t; UIView.animate(withDuration: 0.2) { self.messageLabel.alpha = 1 } }
    private func hideMsg() { UIView.animate(withDuration: 0.2) { self.messageLabel.alpha = 0 } }

    // MARK: - Game Loop
    private func tick() {
        guard !isGameOver else { return }
        let now = CACurrentMediaTime(); let dt = min(now - lastTime, 0.1); lastTime = now
        shootCooldown = max(0, shootCooldown - dt)
        if isShooting && shootCooldown <= 0 && !isReloading && ammo > 0 { tryShoot() }

        // Move player
        if joystickActive {
            let sp: Float = 6
            var fwd = worldFront(of: cameraNode.presentation); fwd.y = 0
            let fl = sqrt(fwd.x*fwd.x + fwd.z*fwd.z)
            let mf = fl > 0 ? SCNVector3(fwd.x/fl, 0, fwd.z/fl) : SCNVector3(0, 0, -1)
            let rt = SCNVector3(mf.z, 0, -mf.x)
            var np = cameraHolder.position
            np.x += rt.x * Float(moveInput.x) * sp * Float(dt) + mf.x * Float(moveInput.y) * sp * Float(dt)
            np.z += rt.z * Float(moveInput.x) * sp * Float(dt) + mf.z * Float(moveInput.y) * sp * Float(dt)
            let half = Float(mapSize/2) - 1.5
            np.x = max(-half, min(half, np.x)); np.z = max(-half, min(half, np.z))
            np.y = playerY
            if !isInsideBarrier(x: np.x, y: np.y, z: np.z) {
                cameraHolder.position = np
            }
        }

        // Bullets
        var rmBullets = IndexSet()
        for i in 0..<bullets.count {
            var bl = bullets[i]
            bl.node.position.x += bl.velocity.x * Float(dt); bl.node.position.y += bl.velocity.y * Float(dt); bl.node.position.z += bl.velocity.z * Float(dt)
            bl.lifetime += dt; bullets[i].lifetime = bl.lifetime; bullets[i].node.position = bl.node.position
            if bl.lifetime > 2.5 { rmBullets.insert(i); bl.node.removeFromParentNode(); continue }
            if bl.node.position.y <= groundTop {
                particles(at: bl.node.position, color: UIColor(white: 0.7, alpha: 1), count: 4)
                rmBullets.insert(i); bl.node.removeFromParentNode(); continue
            }
            // Hit barrier
            if isInsideBarrier(x: bl.node.position.x, y: bl.node.position.y, z: bl.node.position.z) {
                particles(at: bl.node.position, color: UIColor(white: 0.7, alpha: 1), count: 4)
                rmBullets.insert(i); bl.node.removeFromParentNode(); continue
            }
            if bl.isBotBullet {
                if dist(bl.node.position, cameraHolder.position) < 0.7 {
                    hurtPlayer(8); particles(at: bl.node.position, color: .red, count: 5)
                    rmBullets.insert(i); bl.node.removeFromParentNode()
                }
            } else {
                for j in 0..<bots.count where bots[j].alive {
                    let hd = SCNVector3(bots[j].node.presentation.position.x, bots[j].node.presentation.position.y + 1.55, bots[j].node.presentation.position.z)
                    if dist(bl.node.position, hd) < 0.7 {
                        bots[j].hp -= 25; particles(at: bl.node.position, color: .orange, count: 8)
                        rmBullets.insert(i); bl.node.removeFromParentNode()
                        if bots[j].hp <= 0 { bots[j].alive = false; bots[j].node.removeFromParentNode(); kills += 1; score += 100; refreshHUD()
                            if kills >= totalBots { score += hp * 5; refreshHUD(); endGame(won: true) } }
                        break
                    }
                }
            }
        }
        bullets = bullets.enumerated().filter { !rmBullets.contains($0.offset) }.map { $0.element }

        // Bots
        for i in 0..<bots.count where bots[i].alive {
            var bt = bots[i]
            let to = SCNVector3(cameraHolder.position.x - bt.node.position.x, 0, cameraHolder.position.z - bt.node.position.z)
            let d = sqrt(to.x*to.x + to.z*to.z)
            bt.node.eulerAngles.y = atan2(to.x, to.z)
            let spd: Float = 2.5; let mv = d > 0 ? SCNVector3(to.x/d, 0, to.z/d) : SCNVector3(0, 0, 1)
            var np = bt.node.position
            if d > 7 { np.x += mv.x * spd * Float(dt); np.z += mv.z * spd * Float(dt) }
            else if d < 4 { np.x -= mv.x * spd * 0.5 * Float(dt); np.z -= mv.z * spd * 0.5 * Float(dt) }
            else {
                bt.strafeTimer -= dt
                if bt.strafeTimer <= 0 { bt.strafeDir = -bt.strafeDir; bt.strafeTimer = TimeInterval.random(in: 1...3) }
                np.x += -mv.z * bt.strafeDir * spd * 0.6 * Float(dt); np.z += mv.x * bt.strafeDir * spd * 0.6 * Float(dt)
                bots[i].strafeDir = bt.strafeDir; bots[i].strafeTimer = bt.strafeTimer
            }
            np.y = botFootY
            if !isInsideBarrier(x: np.x, y: np.y, z: np.z) { bt.node.position = np }
            bt.shootTimer -= dt
            if bt.shootTimer <= 0 && d < 22 { botFire(bt); bt.shootTimer = TimeInterval.random(in: 1.5...3) }
            bots[i].shootTimer = bt.shootTimer
        }

        // Weapon bob
        weaponNode.position.y = -0.11 + Float(sin(now * (joystickActive ? 8 : 3)) * (joystickActive ? 0.008 : 0.003))
    }

    private func dist(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        let dx = a.x-b.x, dy = a.y-b.y, dz = a.z-b.z; return sqrt(dx*dx + dy*dy + dz*dz)
    }

    /// iOS 10 compatible replacement for `node.worldFront`.
    /// The world front is the -Z axis of the node transformed to world space.
    private func worldFront(of node: SCNNode) -> SCNVector3 {
        let t = node.worldTransform
        return SCNVector3(-t.m31, -t.m32, -t.m33)
    }

    /// Returns true if the point (with margin) is inside a barrier.
    private func isInsideBarrier(x: Float, y: Float, z: Float) -> Bool {
        let margin: Float = 0.4
        for box in barrierBoxes {
            if x + margin > box.minX && x - margin < box.maxX,
               z + margin > box.minZ && z - margin < box.maxZ,
               y > box.minY - 0.3 && y < box.maxY + 0.3 {
                return true
            }
        }
        return false
    }
}
