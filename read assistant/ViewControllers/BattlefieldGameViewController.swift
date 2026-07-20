import UIKit
import SceneKit

// MARK: - Battlefield Game View Controller
/// Minecraft-style 3D battlefield shooting game using SceneKit (iOS 10+).
/// Landscape-only, play against bots. Costs 20 coins per play.
final class BattlefieldGameViewController: UIViewController {
    
    // MARK: - Types
    
    enum PlayerClass { case assault, medic, recon }
    private enum WeaponSlot { case primary, secondary, grenade }
    
    private struct WeaponStats {
        let name: String; let icon: String
        let damage: Int; let fireRate: TimeInterval
        let magSize: Int; let reloadTime: TimeInterval
        let bulletSpeed: Float; let isAuto: Bool
    }
    
    // MARK: - Game State
    private var playerClass: PlayerClass = .assault
    private var currentSlot: WeaponSlot = .primary
    private var hp: Float = 100
    private let maxHp: Float = 100
    private var primaryAmmo: Int = 30; private var primaryReserve: Int = 90
    private var secondaryAmmo: Int = 12; private var secondaryReserve: Int = 36
    private var grenadeCount: Int = 3
    private var kills: Int = 0
    private let totalBots: Int = 8
    private var score: Int = 0
    private var isGameOver: Bool = false
    private var isReloading: Bool = false
    private var shootCooldown: TimeInterval = 0
    private var isShooting: Bool = false
    private var isPaused: Bool = false
    private var inTurret: Bool = false
    private var nearTurret: Bool = false
    private var moveSpeed: Float = 6.0
    private var healCooldown: TimeInterval = 0
    private var isScoped: Bool = false
    private var isSprinting: Bool = false
    private var isJumping: Bool = false
    private var jumpVelocity: Float = 0
    private var medicHealCharges: Int = 2
    private var hasDeployed: Bool = false
    private var playerTickets: Int = 100
    private var enemyTickets: Int = 150
    private var turretAmmo: Int = 100
    private var turretReserve: Int = 300
    private var ticketDrainAccum: Float = 0
    private var ammoNearTimer: Float = 0
    private let playerTicketBar = UIView()
    private let enemyTicketBar = UIView()
    private let playerTicketLabel = UILabel()
    private let enemyTicketLabel = UILabel()

    // Capture points
    private struct CapturePoint {
        let node: SCNNode
        let flagNode: SCNNode
        let label: String
        var progress: Float
    }
    private var capturePoints: [CapturePoint] = []

    // Minimap
    private let minimapView = UIView()
    
    // Weapon data helpers
    private func weaponStats() -> WeaponStats {
        switch currentSlot {
        case .primary:
            if playerClass == .recon {
                return WeaponStats(name: "狙击步枪", icon: "🔭", damage: 80, fireRate: 1.2, magSize: 5, reloadTime: 2.5, bulletSpeed: 100, isAuto: false)
            }
            return WeaponStats(name: "突击步枪", icon: "🎯", damage: 25, fireRate: 0.12, magSize: 30, reloadTime: 1.5, bulletSpeed: 65, isAuto: true)
        case .secondary:
            return WeaponStats(name: "手枪", icon: "🔫", damage: 18, fireRate: 0.3, magSize: 12, reloadTime: 1.0, bulletSpeed: 45, isAuto: false)
        case .grenade:
            return WeaponStats(name: "手雷", icon: "💣", damage: 90, fireRate: 0.8, magSize: 1, reloadTime: 0, bulletSpeed: 12, isAuto: false)
        }
    }
    private var curAmmo: Int {
        get { currentSlot == .secondary ? secondaryAmmo : primaryAmmo }
        set { if currentSlot == .secondary { secondaryAmmo = newValue } else { primaryAmmo = newValue } }
    }
    private var curReserve: Int {
        get { currentSlot == .secondary ? secondaryReserve : primaryReserve }
        set { if currentSlot == .secondary { secondaryReserve = newValue } else { primaryReserve = newValue } }
    }
    private var curMag: Int { weaponStats().magSize }
    
    // MARK: - SceneKit
    private let scnView = SCNView()
    private let scene = SCNScene()
    private let cameraHolder = SCNNode()
    private let cameraNode = SCNNode()
    private let weaponNode = SCNNode()
    private var terrainNodes: [SCNNode] = []
    
    // Bots (with health bar)
    private struct Bot {
        let node: SCNNode
        var hp: Float
        let maxHp: Float
        var alive: Bool
        var shootTimer: TimeInterval
        var strafeDir: Float
        var strafeTimer: TimeInterval
        var hitFlashTimer: TimeInterval
        let hpBarBg: SCNNode
        let hpBarFill: SCNNode
    }
    private var bots: [Bot] = []
    
    // Turret
    private let turretNode = SCNNode()
    private let turretBase = SCNNode()
    private let turretGun = SCNNode()
    private var cpTurretNodes: [SCNNode] = []
    
    // Bullets
    private struct Bullet {
        let node: SCNNode
        var velocity: SCNVector3
        var lifetime: TimeInterval
        var isBotBullet: Bool
        var isGrenade: Bool = false
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
    private let pauseButton = UIButton(type: .custom)
    private let turretButton = UIButton(type: .custom)
    private let scopeButton = UIButton(type: .custom)
    private let jumpButton = UIButton(type: .custom)
    private let sprintButton = UIButton(type: .custom)
    private let healButton = UIButton(type: .custom)
    
    // Weapon bar
    private let weaponBar = UIStackView()
    private let primaryBtn = UIButton(type: .custom)
    private let secondaryBtn = UIButton(type: .custom)
    private let grenadeBtn = UIButton(type: .custom)
    
    // Pause overlay
    private let pauseOverlay = UIView()
    private let scopeOverlay = UIView()
    
    // Game Over / Deploy
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
        setupScopeOverlay()
        buildMinimap()
        buildCaptureHUD()
        buildTicketBars()
        buildJoystick()
        buildButtons()
        buildGameOver()
        generateTerrain()
        spawnCapturePoints()
        spawnAmmoCrates()
        spawnTurret()
        spawnPlayer()
        spawnBots()
        lastTime = CACurrentMediaTime()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in self?.tick() }
        // Show deploy screen at start
        isGameOver = true
        (gameOverView.viewWithTag(100) as? UILabel)?.text = "战地枪战"
        (gameOverView.viewWithTag(100) as? UILabel)?.textColor = .white
        (gameOverView.viewWithTag(101) as? UILabel)?.text = "选择你的部署兵种"
        gameOverView.alpha = 1
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
        updateWeaponModel()
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

    private func updateWeaponModel() {
        weaponNode.childNodes.forEach { $0.removeFromParentNode() }
        let ws = weaponStats()
        let s: Float = 2.0 // Scale factor

        // Body
        let bodyLen: Float = playerClass == .recon ? 0.55 : 0.35
        let bodyGeo = SCNBox(width: CGFloat(0.1 * s), height: CGFloat(0.15 * s), length: CGFloat(bodyLen * s), chamferRadius: 0.02)
        bodyGeo.firstMaterial?.diffuse.contents = UIColor.darkGray
        let bodyNode = SCNNode(geometry: bodyGeo)
        bodyNode.position = SCNVector3(0.25 * s, -0.18 * s, -0.45 * s)
        weaponNode.addChildNode(bodyNode)

        // Barrel
        let barrelLen: Float = playerClass == .recon ? 0.55 : 0.25
        let barrelGeo = SCNBox(width: CGFloat(0.05 * s), height: CGFloat(0.05 * s), length: CGFloat(barrelLen * s), chamferRadius: 0.01)
        barrelGeo.firstMaterial?.diffuse.contents = UIColor.gray
        let barrel = SCNNode(geometry: barrelGeo)
        barrel.position = SCNVector3(0.25 * s, -0.15 * s, -0.45 * s - bodyLen*s/2 - barrelLen*s/2)
        weaponNode.addChildNode(barrel)

        // Sniper scope
        if playerClass == .recon {
            let scopeGeo = SCNCylinder(radius: CGFloat(0.04 * s), height: CGFloat(0.25 * s))
            scopeGeo.firstMaterial?.diffuse.contents = UIColor.black
            let scope = SCNNode(geometry: scopeGeo)
            scope.position = SCNVector3(0.25 * s, -0.03 * s, -0.5 * s)
            weaponNode.addChildNode(scope)

            let lensGeo = SCNCylinder(radius: CGFloat(0.05 * s), height: 0.03)
            lensGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1)
            let lens = SCNNode(geometry: lensGeo)
            lens.position = SCNVector3(0.25 * s, -0.03 * s, -0.5 * s + 0.13 * s)
            weaponNode.addChildNode(lens)
        }

        // Handle
        let handleGeo = SCNBox(width: CGFloat(0.06 * s), height: CGFloat(0.15 * s), length: CGFloat(0.08 * s), chamferRadius: 0.01)
        handleGeo.firstMaterial?.diffuse.contents = UIColor.brown
        let handle = SCNNode(geometry: handleGeo)
        handle.position = SCNVector3(0.25 * s, -0.30 * s, -0.4 * s)
        weaponNode.addChildNode(handle)

        // Clip
        let clipGeo = SCNBox(width: CGFloat(0.05 * s), height: CGFloat(0.12 * s), length: CGFloat(0.06 * s), chamferRadius: 0.005)
        clipGeo.firstMaterial?.diffuse.contents = UIColor(white: 0.2, alpha: 1)
        let clip = SCNNode(geometry: clipGeo)
        clip.position = SCNVector3(0.25 * s, -0.30 * s, -0.38 * s)
        weaponNode.addChildNode(clip)

        weaponNode.position = SCNVector3(0.15, -0.18, -0.5)
    }

    // MARK: - HUD
    private func buildHUD() {
        let bar = UIStackView()
        bar.axis = .horizontal; bar.spacing = 8; bar.alignment = .center
        bar.translatesAutoresizingMaskIntoConstraints = false; bar.isUserInteractionEnabled = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor, constant: 40),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.heightAnchor.constraint(equalToConstant: 28)
        ])
        
        // Health
        let healthBg = UIView()
        healthBg.backgroundColor = UIColor(white: 0, alpha: 0.5)
        healthBg.layer.cornerRadius = 6; healthBg.layer.borderWidth = 1.5
        healthBg.layer.borderColor = UIColor(white: 0.5, alpha: 0.6).cgColor
        healthBg.translatesAutoresizingMaskIntoConstraints = false
        healthBg.widthAnchor.constraint(equalToConstant: 170).isActive = true
        healthBg.heightAnchor.constraint(equalToConstant: 24).isActive = true
        
        healthFill.backgroundColor = UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
        healthFill.layer.cornerRadius = 5; healthFill.translatesAutoresizingMaskIntoConstraints = false
        healthBg.addSubview(healthFill)
        NSLayoutConstraint.activate([
            healthFill.leadingAnchor.constraint(equalTo: healthBg.leadingAnchor, constant: 2),
            healthFill.centerYAnchor.constraint(equalTo: healthBg.centerYAnchor),
            healthFill.widthAnchor.constraint(equalToConstant: 166), healthFill.heightAnchor.constraint(equalToConstant: 20)
        ])
        healthLabel.text = "❤️ 100"; healthLabel.textColor = .white; healthLabel.font = .boldSystemFont(ofSize: 12)
        healthLabel.textAlignment = .center; healthLabel.translatesAutoresizingMaskIntoConstraints = false
        healthBg.addSubview(healthLabel)
        healthLabel.centerXAnchor.constraint(equalTo: healthBg.centerXAnchor).isActive = true
        healthLabel.centerYAnchor.constraint(equalTo: healthBg.centerYAnchor).isActive = true
        bar.addArrangedSubview(healthBg)
        
        // Ammo
        ammoLabel.text = "🎯 30/90"; ammoLabel.textColor = .white; ammoLabel.font = .boldSystemFont(ofSize: 13)
        ammoLabel.backgroundColor = UIColor(white: 0, alpha: 0.5); ammoLabel.layer.cornerRadius = 6
        ammoLabel.layer.borderWidth = 1.5; ammoLabel.layer.borderColor = UIColor(white: 0.5, alpha: 0.6).cgColor
        ammoLabel.clipsToBounds = true; ammoLabel.textAlignment = .center
        ammoLabel.widthAnchor.constraint(equalToConstant: 75).isActive = true
        ammoLabel.heightAnchor.constraint(equalToConstant: 28).isActive = true
        bar.addArrangedSubview(ammoLabel)
        
        killsLabel.text = "💀 0/8"; killsLabel.textColor = .white; killsLabel.font = .boldSystemFont(ofSize: 14)
        killsLabel.backgroundColor = UIColor(white: 0, alpha: 0.5); killsLabel.layer.cornerRadius = 6
        killsLabel.layer.borderWidth = 1.5; killsLabel.layer.borderColor = UIColor(white: 0.5, alpha: 0.6).cgColor
        killsLabel.clipsToBounds = true; killsLabel.textAlignment = .center
        killsLabel.widthAnchor.constraint(equalToConstant: 68).isActive = true
        killsLabel.heightAnchor.constraint(equalToConstant: 28).isActive = true
        bar.addArrangedSubview(killsLabel)
        
        scoreLabel.text = "⭐ 0"; scoreLabel.textColor = UIColor(red: 1, green: 0.85, blue: 0, alpha: 1)
        scoreLabel.font = .boldSystemFont(ofSize: 14); scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scoreLabel)
        NSLayoutConstraint.activate([
            scoreLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scoreLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])
        
        // Pause button
        pauseButton.setTitle("⏸", for: .normal); pauseButton.titleLabel?.font = .systemFont(ofSize: 22)
        pauseButton.backgroundColor = UIColor(white: 0, alpha: 0.4); pauseButton.layer.cornerRadius = 16
        pauseButton.translatesAutoresizingMaskIntoConstraints = false
        pauseButton.addTarget(self, action: #selector(togglePause), for: .touchUpInside)
        view.addSubview(pauseButton)
        NSLayoutConstraint.activate([
            pauseButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            pauseButton.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            pauseButton.widthAnchor.constraint(equalToConstant: 32), pauseButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        // Turret enter/exit button (hidden by default)
        turretButton.setTitle("进入炮台", for: .normal); turretButton.titleLabel?.font = .boldSystemFont(ofSize: 14)
        turretButton.backgroundColor = UIColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 0.8)
        turretButton.layer.cornerRadius = 8; turretButton.isHidden = true
        turretButton.translatesAutoresizingMaskIntoConstraints = false
        turretButton.addTarget(self, action: #selector(toggleTurret), for: .touchUpInside)
        view.addSubview(turretButton)
        NSLayoutConstraint.activate([
            turretButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            turretButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -30),
            turretButton.widthAnchor.constraint(equalToConstant: 100), turretButton.heightAnchor.constraint(equalToConstant: 36)
        ])
        
        // Weapon bar at bottom center
        weaponBar.axis = .horizontal; weaponBar.spacing = 6; weaponBar.alignment = .center
        weaponBar.distribution = .fillEqually; weaponBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(weaponBar)
        NSLayoutConstraint.activate([
            weaponBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            weaponBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            weaponBar.widthAnchor.constraint(equalToConstant: 200), weaponBar.heightAnchor.constraint(equalToConstant: 40)
        ])
        func makeWepBtn(_ btn: UIButton, _ icon: String, _ tag: Int, _ sel: Selector) {
            btn.setTitle(icon, for: .normal); btn.titleLabel?.font = .systemFont(ofSize: 20)
            btn.backgroundColor = UIColor(white: 0, alpha: 0.45); btn.layer.cornerRadius = 8
            btn.layer.borderWidth = 2; btn.layer.borderColor = UIColor(white: 0.4, alpha: 0.5).cgColor
            btn.tag = tag; btn.addTarget(self, action: sel, for: .touchUpInside)
            weaponBar.addArrangedSubview(btn)
        }
        makeWepBtn(primaryBtn, "🎯", 0, #selector(onWeaponTap))
        makeWepBtn(secondaryBtn, "🔫", 1, #selector(onWeaponTap))
        makeWepBtn(grenadeBtn, "💣3", 2, #selector(onWeaponTap))
        highlightWeaponSlot()
        
        // Crosshair, message, pause overlay
        crosshairView.image = drawCrosshairImage(); crosshairView.contentMode = .center
        crosshairView.isUserInteractionEnabled = false; crosshairView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(crosshairView)
        NSLayoutConstraint.activate([
            crosshairView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            crosshairView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            crosshairView.widthAnchor.constraint(equalToConstant: 36), crosshairView.heightAnchor.constraint(equalToConstant: 36)
        ])
        
        messageLabel.textColor = UIColor(red: 1, green: 0.85, blue: 0, alpha: 1)
        messageLabel.font = .boldSystemFont(ofSize: 24); messageLabel.textAlignment = .center
        messageLabel.isUserInteractionEnabled = false; messageLabel.alpha = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageLabel)
        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50)
        ])
        
        // Pause overlay
        pauseOverlay.backgroundColor = UIColor(white: 0, alpha: 0.6); pauseOverlay.alpha = 0
        pauseOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pauseOverlay)
        NSLayoutConstraint.activate([
            pauseOverlay.topAnchor.constraint(equalTo: view.topAnchor), pauseOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pauseOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor), pauseOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let pauseLabel = UILabel(); pauseLabel.text = "游戏暂停"; pauseLabel.textColor = .white
        pauseLabel.font = .boldSystemFont(ofSize: 36); pauseLabel.textAlignment = .center
        pauseLabel.translatesAutoresizingMaskIntoConstraints = false; pauseOverlay.addSubview(pauseLabel)
        NSLayoutConstraint.activate([
            pauseLabel.centerXAnchor.constraint(equalTo: pauseOverlay.centerXAnchor),
            pauseLabel.centerYAnchor.constraint(equalTo: pauseOverlay.centerYAnchor, constant: -40)
        ])
        let resumeBtn = UIButton(type: .system); resumeBtn.setTitle("继续游戏 ▶", for: .normal)
        resumeBtn.titleLabel?.font = .boldSystemFont(ofSize: 22); resumeBtn.setTitleColor(.white, for: .normal)
        resumeBtn.backgroundColor = UIColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1); resumeBtn.layer.cornerRadius = 12
        resumeBtn.translatesAutoresizingMaskIntoConstraints = false
        resumeBtn.addTarget(self, action: #selector(togglePause), for: .touchUpInside)
        pauseOverlay.addSubview(resumeBtn)
        NSLayoutConstraint.activate([
            resumeBtn.centerXAnchor.constraint(equalTo: pauseOverlay.centerXAnchor),
            resumeBtn.topAnchor.constraint(equalTo: pauseLabel.bottomAnchor, constant: 30),
            resumeBtn.widthAnchor.constraint(equalToConstant: 200), resumeBtn.heightAnchor.constraint(equalToConstant: 50)
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

    private func setupScopeOverlay() {
        scopeOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        scopeOverlay.isUserInteractionEnabled = false; scopeOverlay.alpha = 0
        scopeOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scopeOverlay)
        NSLayoutConstraint.activate([
            scopeOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            scopeOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scopeOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scopeOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let cr: CGFloat = 140
        let cross = UIView(); cross.backgroundColor = .clear; cross.isUserInteractionEnabled = false
        cross.tag = 500
        cross.translatesAutoresizingMaskIntoConstraints = false; scopeOverlay.addSubview(cross)
        NSLayoutConstraint.activate([
            cross.centerXAnchor.constraint(equalTo: scopeOverlay.centerXAnchor),
            cross.centerYAnchor.constraint(equalTo: scopeOverlay.centerYAnchor),
            cross.widthAnchor.constraint(equalToConstant: cr*2), cross.heightAnchor.constraint(equalToConstant: cr*2)
        ])
        // Draw crosshair via CAShapeLayer for reliable rendering
        let crossLayer = CAShapeLayer()
        let cp = UIBezierPath()
        cp.move(to: CGPoint(x: cr, y: 20)); cp.addLine(to: CGPoint(x: cr, y: cr*2 - 20))
        cp.move(to: CGPoint(x: 20, y: cr)); cp.addLine(to: CGPoint(x: cr*2 - 20, y: cr))
        crossLayer.path = cp.cgPath; crossLayer.strokeColor = UIColor.white.withAlphaComponent(0.5).cgColor
        crossLayer.lineWidth = 2
        cross.layer.addSublayer(crossLayer)
        // Dot in center
        let dotLayer = CAShapeLayer()
        let dotPath = UIBezierPath(ovalIn: CGRect(x: cr - 3, y: cr - 3, width: 6, height: 6))
        dotLayer.path = dotPath.cgPath; dotLayer.fillColor = UIColor.red.withAlphaComponent(0.6).cgColor
        cross.layer.addSublayer(dotLayer)
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

        // Camera rotation via drag on blank canvas — multi-touch capable
        let lookPan = UIPanGestureRecognizer(target: self, action: #selector(onLookPan))
        lookPan.minimumNumberOfTouches = 1; lookPan.maximumNumberOfTouches = 2
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
        cameraNode.eulerAngles.x = max(-Float.pi / 3, min(Float.pi / 3, cameraNode.eulerAngles.x))
        g.setTranslation(.zero, in: scnView)
    }
    private func buildButtons() {
        // Shoot
        shootButton.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        shootButton.backgroundColor = UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.35)
        shootButton.layer.cornerRadius = 40; shootButton.layer.borderWidth = 2.5
        shootButton.layer.borderColor = UIColor(red: 1, green: 0.4, blue: 0.4, alpha: 0.6).cgColor
        shootButton.setTitle("💥", for: .normal); shootButton.titleLabel?.font = .systemFont(ofSize: 30)
        shootButton.translatesAutoresizingMaskIntoConstraints = false
        shootButton.addTarget(self, action: #selector(shootTapDown), for: .touchDown)
        shootButton.addTarget(self, action: #selector(shootTapUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        view.addSubview(shootButton)
        NSLayoutConstraint.activate([
            shootButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            shootButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -60),
            shootButton.widthAnchor.constraint(equalToConstant: 80), shootButton.heightAnchor.constraint(equalToConstant: 80)
        ])

        // Reload
        reloadButton.frame = CGRect(x: 0, y: 0, width: 46, height: 46)
        reloadButton.backgroundColor = UIColor(red: 1, green: 0.75, blue: 0.1, alpha: 0.25)
        reloadButton.layer.cornerRadius = 23; reloadButton.layer.borderWidth = 2
        reloadButton.layer.borderColor = UIColor(red: 1, green: 0.75, blue: 0.1, alpha: 0.5).cgColor
        reloadButton.setTitle("🔄", for: .normal); reloadButton.titleLabel?.font = .systemFont(ofSize: 18)
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.addTarget(self, action: #selector(reloadTap), for: .touchUpInside)
        view.addSubview(reloadButton)
        NSLayoutConstraint.activate([
            reloadButton.trailingAnchor.constraint(equalTo: shootButton.leadingAnchor, constant: -10),
            reloadButton.centerYAnchor.constraint(equalTo: shootButton.centerYAnchor, constant: -14),
            reloadButton.widthAnchor.constraint(equalToConstant: 46), reloadButton.heightAnchor.constraint(equalToConstant: 46)
        ])

        // Scope (recon only)
        scopeButton.frame = CGRect(x: 0, y: 0, width: 46, height: 46)
        scopeButton.backgroundColor = UIColor(white: 0, alpha: 0.4); scopeButton.layer.cornerRadius = 23
        scopeButton.layer.borderWidth = 2; scopeButton.layer.borderColor = UIColor(white: 0.5, alpha: 0.6).cgColor
        scopeButton.setTitle("🔍", for: .normal); scopeButton.titleLabel?.font = .systemFont(ofSize: 18)
        scopeButton.translatesAutoresizingMaskIntoConstraints = false
        scopeButton.addTarget(self, action: #selector(toggleScope), for: .touchUpInside)
        scopeButton.isHidden = true
        view.addSubview(scopeButton)
        NSLayoutConstraint.activate([
            scopeButton.trailingAnchor.constraint(equalTo: shootButton.leadingAnchor, constant: -10),
            scopeButton.bottomAnchor.constraint(equalTo: reloadButton.topAnchor, constant: -4),
            scopeButton.widthAnchor.constraint(equalToConstant: 46), scopeButton.heightAnchor.constraint(equalToConstant: 46)
        ])

        // Jump (assault only)
        jumpButton.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        jumpButton.backgroundColor = UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 0.3)
        jumpButton.layer.cornerRadius = 25; jumpButton.layer.borderWidth = 2
        jumpButton.layer.borderColor = UIColor(red: 0.4, green: 0.6, blue: 1, alpha: 0.5).cgColor
        jumpButton.setTitle("⬆️", for: .normal); jumpButton.titleLabel?.font = .systemFont(ofSize: 20)
        jumpButton.translatesAutoresizingMaskIntoConstraints = false; jumpButton.isHidden = true
        jumpButton.addTarget(self, action: #selector(jumpTap), for: .touchUpInside)
        view.addSubview(jumpButton)
        NSLayoutConstraint.activate([
            jumpButton.centerXAnchor.constraint(equalTo: shootButton.centerXAnchor),
            jumpButton.bottomAnchor.constraint(equalTo: shootButton.topAnchor, constant: -8),
            jumpButton.widthAnchor.constraint(equalToConstant: 50), jumpButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        // Sprint (assault only)
        sprintButton.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        sprintButton.backgroundColor = UIColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 0.25)
        sprintButton.layer.cornerRadius = 25; sprintButton.layer.borderWidth = 2
        sprintButton.layer.borderColor = UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 0.5).cgColor
        sprintButton.setTitle("🏃", for: .normal); sprintButton.titleLabel?.font = .systemFont(ofSize: 20)
        sprintButton.translatesAutoresizingMaskIntoConstraints = false; sprintButton.isHidden = true
        sprintButton.addTarget(self, action: #selector(sprintTapDown), for: .touchDown)
        sprintButton.addTarget(self, action: #selector(sprintTapUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        view.addSubview(sprintButton)
        NSLayoutConstraint.activate([
            sprintButton.centerXAnchor.constraint(equalTo: reloadButton.centerXAnchor),
            sprintButton.bottomAnchor.constraint(equalTo: reloadButton.topAnchor, constant: -4),
            sprintButton.widthAnchor.constraint(equalToConstant: 50), sprintButton.heightAnchor.constraint(equalToConstant: 50)
        ])

        // Heal (medic only)
        healButton.frame = CGRect(x: 0, y: 0, width: 46, height: 46)
        healButton.backgroundColor = UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 0.25)
        healButton.layer.cornerRadius = 23; healButton.layer.borderWidth = 2
        healButton.layer.borderColor = UIColor(red: 0.3, green: 0.8, blue: 0.4, alpha: 0.5).cgColor
        healButton.setTitle("💊", for: .normal); healButton.titleLabel?.font = .systemFont(ofSize: 18)
        healButton.translatesAutoresizingMaskIntoConstraints = false; healButton.isHidden = true
        healButton.addTarget(self, action: #selector(healTap), for: .touchUpInside)
        view.addSubview(healButton)
        NSLayoutConstraint.activate([
            healButton.trailingAnchor.constraint(equalTo: shootButton.leadingAnchor, constant: -10),
            healButton.bottomAnchor.constraint(equalTo: scopeButton.topAnchor, constant: -4),
            healButton.widthAnchor.constraint(equalToConstant: 46), healButton.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    @objc private func shootTapDown() { if !isPaused { isShooting = true; if currentSlot == .grenade { throwGrenade() } else { tryShoot() } } }
    @objc private func shootTapUp() { isShooting = false }
    @objc private func reloadTap() { reload() }

    @objc private func toggleScope() {
        isScoped = !isScoped
        cameraNode.camera?.xFov = isScoped ? 12 : 55
        cameraNode.camera?.yFov = isScoped ? 12 : 55
        if isScoped {
            let b = scopeOverlay.bounds; let cr: CGFloat = 140
            let mask = CAShapeLayer()
            let path = UIBezierPath(rect: b)
            path.append(UIBezierPath(ovalIn: CGRect(x: b.midX - cr, y: b.midY - cr, width: cr*2, height: cr*2)))
            mask.path = path.cgPath; mask.fillRule = .evenOdd
            scopeOverlay.layer.mask = mask
        }
        scopeOverlay.alpha = isScoped ? 1 : 0
        crosshairView.isHidden = isScoped
    }

    @objc private func jumpTap() {
        guard !isJumping, !inTurret else { return }
        isJumping = true; jumpVelocity = 8
    }

    @objc private func sprintTapDown() { isSprinting = true }
    @objc private func sprintTapUp() { isSprinting = false }

    @objc private func healTap() {
        guard medicHealCharges > 0, hp < maxHp else { return }
        hp = min(maxHp, hp + 50); medicHealCharges -= 1
        refreshHUD(); showMsg("+50 ❤️"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.hideMsg() }
    }
    
    @objc private func onWeaponTap(_ sender: UIButton) {
        let slots: [WeaponSlot] = [.primary, .secondary, .grenade]
        guard sender.tag < slots.count else { return }
        currentSlot = slots[sender.tag]
        highlightWeaponSlot()
        if currentSlot != .grenade { updateWeaponModel() } else { weaponNode.childNodes.forEach { $0.removeFromParentNode() } }
        refreshHUD()
    }
    private func highlightWeaponSlot() {
        for (i, btn) in [primaryBtn, secondaryBtn, grenadeBtn].enumerated() {
            let active = i == (currentSlot == .primary ? 0 : currentSlot == .secondary ? 1 : 2)
            btn.layer.borderColor = active ? UIColor.white.cgColor : UIColor(white: 0.4, alpha: 0.5).cgColor
            btn.backgroundColor = active ? UIColor(white: 1, alpha: 0.2) : UIColor(white: 0, alpha: 0.45)
        }
    }
    
    @objc private func togglePause() {
        isPaused = !isPaused
        if isPaused { lastTime = CACurrentMediaTime() }
        UIView.animate(withDuration: 0.25) { self.pauseOverlay.alpha = self.isPaused ? 1 : 0 }
    }
    
    @objc private func toggleTurret() {
        inTurret = !inTurret
        if inTurret {
            // Find nearest turret
            var nearest = turretNode
            var minDist: Float = dist(cameraHolder.position, turretNode.position)
            for t in cpTurretNodes {
                let d = dist(cameraHolder.position, t.position)
                if d < minDist { minDist = d; nearest = t }
            }
            cameraHolder.position = SCNVector3(nearest.position.x, nearest.position.y + 1.2, nearest.position.z)
            cameraNode.eulerAngles = nearest.eulerAngles
            moveSpeed = 0
            turretButton.setTitle("退出炮台", for: .normal)
        } else {
            cameraHolder.position = SCNVector3(cameraHolder.position.x + 2, playerY, cameraHolder.position.z)
            cameraNode.eulerAngles = SCNVector3(0, 0, 0)
            moveSpeed = playerClass == .recon ? 6.5 : (playerClass == .medic ? 5.5 : 6.0)
            turretButton.setTitle("進入炮台", for: .normal)
        }
    }
    
    // MARK: - Game Over / Deploy
    private func buildGameOver() {
        gameOverView.backgroundColor = UIColor(white: 0, alpha: 0.88)
        gameOverView.alpha = 0; gameOverView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gameOverView)
        NSLayoutConstraint.activate([
            gameOverView.topAnchor.constraint(equalTo: view.topAnchor), gameOverView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gameOverView.trailingAnchor.constraint(equalTo: view.trailingAnchor), gameOverView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        let title = UILabel(); title.tag = 100; title.textColor = .white
        title.font = .boldSystemFont(ofSize: 36); title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false; gameOverView.addSubview(title)
        
        let sub = UILabel(); sub.tag = 101; sub.textColor = UIColor(white: 0.8, alpha: 1)
        sub.font = .systemFont(ofSize: 17); sub.textAlignment = .center; sub.numberOfLines = 0
        sub.translatesAutoresizingMaskIntoConstraints = false; gameOverView.addSubview(sub)
        
        let deployLabel = UILabel(); deployLabel.tag = 102
        deployLabel.text = "选择部署兵种:"; deployLabel.textColor = UIColor(red: 1, green: 0.85, blue: 0, alpha: 1)
        deployLabel.font = .boldSystemFont(ofSize: 20); deployLabel.textAlignment = .center
        deployLabel.translatesAutoresizingMaskIntoConstraints = false; gameOverView.addSubview(deployLabel)
        
        let classStack = UIStackView(); classStack.axis = .horizontal; classStack.spacing = 16
        classStack.alignment = .center; classStack.distribution = .fillEqually; classStack.tag = 200
        classStack.translatesAutoresizingMaskIntoConstraints = false; gameOverView.addSubview(classStack)
        
        func makeClassBtn(_ title: String, _ desc: String, _ tag: Int) -> UIButton {
            let b = UIButton(type: .system); b.tag = tag
            b.setTitle("\(title)\n\(desc)", for: .normal); b.titleLabel?.numberOfLines = 3
            b.titleLabel?.textAlignment = .center; b.titleLabel?.font = .systemFont(ofSize: 14)
            b.setTitleColor(.white, for: .normal); b.backgroundColor = UIColor(white: 0.2, alpha: 1)
            b.layer.cornerRadius = 12; b.layer.borderWidth = 2; b.layer.borderColor = UIColor(white: 0.4, alpha: 1).cgColor
            b.addTarget(self, action: #selector(deployClassTap), for: .touchUpInside)
            return b
        }
        classStack.addArrangedSubview(makeClassBtn("🔫 突击兵", "步枪+手枪+3手雷\n生命100 速度正常", 0))
        classStack.addArrangedSubview(makeClassBtn("💉 医疗兵", "步枪+手枪+2手雷\n生命100 可自疗", 1))
        classStack.addArrangedSubview(makeClassBtn("🔭 侦察兵", "狙击+手枪+2手雷\n生命80 速度快", 2))
        
        let exitBtn = UIButton(type: .system); exitBtn.setTitle("退出游戏", for: .normal)
        exitBtn.titleLabel?.font = .boldSystemFont(ofSize: 16)
        exitBtn.setTitleColor(UIColor(white: 0.7, alpha: 1), for: .normal)
        exitBtn.addTarget(self, action: #selector(exitTap), for: .touchUpInside)
        exitBtn.translatesAutoresizingMaskIntoConstraints = false; gameOverView.addSubview(exitBtn)
        
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            title.topAnchor.constraint(equalTo: gameOverView.topAnchor, constant: 40),
            sub.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            deployLabel.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            deployLabel.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 24),
            classStack.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            classStack.topAnchor.constraint(equalTo: deployLabel.bottomAnchor, constant: 12),
            classStack.widthAnchor.constraint(equalToConstant: 340), classStack.heightAnchor.constraint(equalToConstant: 90),
            exitBtn.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            exitBtn.topAnchor.constraint(equalTo: classStack.bottomAnchor, constant: 24)
        ])
    }
    
    @objc private func deployClassTap(_ sender: UIButton) {
        let classes: [PlayerClass] = [.assault, .medic, .recon]
        guard sender.tag < classes.count else { return }
        playerClass = classes[sender.tag]
        switch playerClass {
        case .assault: hp = 100; moveSpeed = 6.0; primaryReserve = 90; secondaryReserve = 36; grenadeCount = 3; medicHealCharges = 0
        case .medic:   hp = 100; moveSpeed = 5.5; primaryReserve = 60; secondaryReserve = 24; grenadeCount = 2; medicHealCharges = 2
        case .recon:   hp = 80;  moveSpeed = 6.5; primaryReserve = 20; secondaryReserve = 24; grenadeCount = 2; medicHealCharges = 0
        }
        jumpButton.isHidden = playerClass != .assault
        sprintButton.isHidden = playerClass != .assault
        healButton.isHidden = playerClass != .medic
        scopeButton.isHidden = playerClass != .recon
        isScoped = false; cameraNode.camera?.xFov = 55; cameraNode.camera?.yFov = 55
        currentSlot = .primary; primaryAmmo = curMag; secondaryAmmo = 12
        updateWeaponModel()
        isGameOver = false; isReloading = false; shootCooldown = 0; isShooting = false; healCooldown = 0
        isJumping = false; isSprinting = false; jumpVelocity = 0; hasDeployed = true
        playerTickets = 100; enemyTickets = 150; turretAmmo = 100; turretReserve = 300; ticketDrainAccum = 0; updateTicketBars()
        for b in bots { b.node.removeFromParentNode() }; bots.removeAll()
        for b in bullets { b.node.removeFromParentNode() }; bullets.removeAll()
        for p in particleNodes { p.removeFromParentNode() }; particleNodes.removeAll()
        spawnPlayer(); spawnBots(); refreshHUD()
        // Reset deploy screen for next death
        gameOverView.viewWithTag(102)?.isHidden = false
        gameOverView.viewWithTag(200)?.isHidden = false
        UIView.animate(withDuration: 0.3) { self.gameOverView.alpha = 0 }
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
        
        // Barriers: varied, asymmetric layout with interesting cover patterns
        let barriers: [(Float, Float, Int, Int, Int)] = [
            // North area - bunker complex
            (-10, -16, 6, 1, 2), (-4, -14, 1, 3, 2), (8, -18, 3, 1, 2),
            (14, -14, 1, 4, 2), (-18, -12, 2, 1, 2), (18, -10, 2, 2, 2),
            // Center-left maze
            (-8, -8, 1, 5, 2), (-14, -4, 4, 1, 2), (-4, -4, 1, 3, 3),
            (-12, 0, 5, 1, 2), (-6, 2, 1, 4, 2), (-18, 4, 2, 1, 2),
            // Center-right crates
            (8, -6, 3, 1, 2), (4, -4, 1, 3, 2), (14, -4, 4, 1, 2),
            (10, 0, 1, 4, 2), (14, 2, 1, 4, 2), (12, 6, 4, 1, 2),
            // South area
            (-6, -18, 3, 1, 2), (0, -16, 1, 3, 2), (2, -12, 4, 1, 2),
            (-14, 8, 1, 4, 2), (-8, 10, 4, 1, 2), (-16, 14, 2, 1, 2),
            // Southeast
            (6, 10, 1, 5, 2), (10, 14, 4, 1, 2), (16, 8, 2, 2, 2),
            // Northeast scattered
            (-2, 16, 1, 3, 2), (4, 16, 1, 3, 2), (-10, 18, 3, 1, 2),
            // Mid scattered single blocks for peeking
            (0, -4, 1, 1, 2), (2, 2, 1, 1, 2), (-4, 6, 1, 1, 2),
            // Far corners
            (-20, -20, 1, 2, 2), (20, -20, 2, 1, 2), (-20, 20, 2, 1, 2), (20, 18, 1, 2, 2),
            // Diagonal cover
            (6, -10, 1, 1, 3), (-8, 2, 1, 1, 3), (10, -2, 1, 1, 3),
        ]
        
        for (cx, cz, bw, bd, bh) in barriers {
            // Compute exact block range from center and size
            let bxStart = Int(round(cx - Float(bw - 1) / 2))
            let bxEnd = Int(round(cx + Float(bw - 1) / 2))
            let bzStart = Int(round(cz - Float(bd - 1) / 2))
            let bzEnd = Int(round(cz + Float(bd - 1) / 2))
            // Collision box = exact block extents
            barrierBoxes.append(BBox(
                minX: Float(bxStart) - 0.5, maxX: Float(bxEnd) + 0.5,
                minZ: Float(bzStart) - 0.5, maxZ: Float(bzEnd) + 0.5,
                minY: groundTop, maxY: groundTop + Float(bh)))
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
            UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1), UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1),
            UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1), UIColor(red: 0.7, green: 0.4, blue: 0.1, alpha: 1),
            UIColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1), UIColor(red: 0.1, green: 0.6, blue: 0.7, alpha: 1),
            UIColor(red: 0.8, green: 0.5, blue: 0, alpha: 1),   UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1),
        ]
        for i in 0..<totalBots {
            var bx: Int, bz: Int
            repeat {
                bx = Int.random(in: (-mapSize/2+3)...(mapSize/2-4))
                bz = Int.random(in: (-mapSize/2+3)...(mapSize/2-4))
            } while (abs(bx) < 5 && abs(bz) < 5) || isInsideBarrier(x: Float(bx), y: botFootY, z: Float(bz))
            let n = makeBot(colors[i])
            n.position = SCNVector3(Float(bx), botFootY, Float(bz))
            scene.rootNode.addChildNode(n)
            
            // Health bar above bot
            let hpBg = SCNNode(geometry: {
                let p = SCNPlane(width: 0.5, height: 0.06)
                p.firstMaterial?.diffuse.contents = UIColor(white: 0.15, alpha: 1); return p
            }())
            hpBg.position = SCNVector3(0, 1.9, 0)
            hpBg.constraints = [SCNBillboardConstraint()]
            n.addChildNode(hpBg)
            
            let hpFill = SCNNode(geometry: {
                let p = SCNPlane(width: 0.5, height: 0.04)
                p.firstMaterial?.diffuse.contents = UIColor.green; return p
            }())
            hpFill.position = SCNVector3(0, 0, 0.01)
            hpFill.pivot = SCNMatrix4MakeTranslation(-0.25, 0, 0)
            hpBg.addChildNode(hpFill)

            bots.append(Bot(node: n, hp: 50, maxHp: 50, alive: true,
                            shootTimer: TimeInterval.random(in: 1...2.5), strafeDir: Bool.random() ? 1 : -1,
                            strafeTimer: TimeInterval.random(in: 1...3), hitFlashTimer: 0,
                            hpBarBg: hpBg, hpBarFill: hpFill))
        }
    }

    private func spawnCapturePoints() {
        let locs: [(Float, Float, String)] = [(-18, -18, "A"), (18, -18, "B"), (-18, 18, "C"), (18, 18, "D")]
        for (x, z, label) in locs {
            let pole = SCNCylinder(radius: 0.08, height: 2.5)
            pole.firstMaterial?.diffuse.contents = UIColor(white: 0.5, alpha: 1)
            let poleNode = SCNNode(geometry: pole)
            poleNode.position = SCNVector3(x, groundTop + 1.25, z)
            scene.rootNode.addChildNode(poleNode)
            let flag = SCNBox(width: 0.8, height: 0.5, length: 0.05, chamferRadius: 0.01)
            flag.firstMaterial?.diffuse.contents = UIColor.white
            let flagNode = SCNNode(geometry: flag)
            flagNode.position = SCNVector3(x + 0.4, groundTop + 2.3, z)
            scene.rootNode.addChildNode(flagNode)
            let baseG = SCNBox(width: 1.5, height: 0.2, length: 1.5, chamferRadius: 0.02)
            baseG.firstMaterial?.diffuse.contents = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
            let baseNode = SCNNode(geometry: baseG)
            baseNode.position = SCNVector3(x, groundTop + 0.1, z)
            scene.rootNode.addChildNode(baseNode)
            let group = SCNNode(); group.position = SCNVector3(x, groundTop, z)
            scene.rootNode.addChildNode(group)
            capturePoints.append(CapturePoint(node: group, flagNode: flagNode, label: label, progress: 0))
            // Defensive turret near each capture point (enterable)
            let tGroup = SCNNode()
            let tBase = SCNBox(width: 1.0, height: 0.7, length: 1.0, chamferRadius: 0.03)
            tBase.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.35, blue: 0.3, alpha: 1)
            let tBaseNode = SCNNode(geometry: tBase)
            tBaseNode.position = SCNVector3(0, groundTop + 0.35, 0)
            tGroup.addChildNode(tBaseNode)
            let tBarrel = SCNCylinder(radius: 0.07, height: 0.9)
            tBarrel.firstMaterial?.diffuse.contents = UIColor.darkGray
            let tBarrelNode = SCNNode(geometry: tBarrel)
            tBarrelNode.eulerAngles.x = Float.pi / 2
            tBarrelNode.position = SCNVector3(0, groundTop + 0.55, 0.3)
            tGroup.addChildNode(tBarrelNode)
            tGroup.position = SCNVector3(x + 1.5, groundTop, z)
            scene.rootNode.addChildNode(tGroup)
            cpTurretNodes.append(tGroup)
        }
    }

    private func buildMinimap() {
        minimapView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        minimapView.layer.borderWidth = 1.5; minimapView.layer.borderColor = UIColor(white: 0.5, alpha: 0.6).cgColor
        minimapView.layer.cornerRadius = 4; minimapView.clipsToBounds = true
        minimapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(minimapView)
        NSLayoutConstraint.activate([
            minimapView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            minimapView.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor, constant: 100),
            minimapView.widthAnchor.constraint(equalToConstant: 90), minimapView.heightAnchor.constraint(equalToConstant: 90)
        ])
    }

    private func buildCaptureHUD() {
        let stack = UIStackView(); stack.axis = .horizontal; stack.spacing = 6; stack.alignment = .center
        stack.distribution = .fillEqually; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor, constant: 68),
            stack.widthAnchor.constraint(equalToConstant: 200), stack.heightAnchor.constraint(equalToConstant: 20)
        ])
        for (i, label) in ["A", "B", "C", "D"].enumerated() {
            let lbl = UILabel(); lbl.text = label; lbl.textColor = UIColor(white: 0.6, alpha: 1)
            lbl.font = .boldSystemFont(ofSize: 12); lbl.textAlignment = .center
            lbl.backgroundColor = UIColor(white: 0, alpha: 0.4); lbl.layer.cornerRadius = 4; lbl.clipsToBounds = true
            lbl.tag = 300 + i
            lbl.widthAnchor.constraint(equalToConstant: 44).isActive = true
            lbl.heightAnchor.constraint(equalToConstant: 20).isActive = true
            stack.addArrangedSubview(lbl)
        }
    }

    private func buildTicketBars() {
        let container = UIStackView(); container.axis = .horizontal; container.spacing = 6
        container.alignment = .center; container.distribution = .fillEqually
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor, constant: 4),
            container.widthAnchor.constraint(equalToConstant: 300), container.heightAnchor.constraint(equalToConstant: 28)
        ])
        func makeTicketBar(_ bar: UIView, _ label: UILabel, _ color: UIColor, _ alignRight: Bool) {
            let bg = UIView(); bg.backgroundColor = UIColor(white: 0, alpha: 0.5)
            bg.layer.cornerRadius = 5; bg.clipsToBounds = true
            bg.translatesAutoresizingMaskIntoConstraints = false
            bar.backgroundColor = color; bar.translatesAutoresizingMaskIntoConstraints = false
            bg.addSubview(bar)
            if alignRight {
                NSLayoutConstraint.activate([
                    bar.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
                    bar.topAnchor.constraint(equalTo: bg.topAnchor),
                    bar.heightAnchor.constraint(equalTo: bg.heightAnchor),
                    bar.widthAnchor.constraint(equalToConstant: 100)
                ])
            } else {
                NSLayoutConstraint.activate([
                    bar.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
                    bar.topAnchor.constraint(equalTo: bg.topAnchor),
                    bar.heightAnchor.constraint(equalTo: bg.heightAnchor),
                    bar.widthAnchor.constraint(equalToConstant: 100)
                ])
            }
            label.textColor = .white; label.font = .boldSystemFont(ofSize: 11)
            label.textAlignment = .center
            let row = UIStackView(); row.axis = .horizontal; row.spacing = 3; row.alignment = .center
            if alignRight { row.addArrangedSubview(bg); row.addArrangedSubview(label) }
            else { row.addArrangedSubview(label); row.addArrangedSubview(bg) }
            container.addArrangedSubview(row)
        }
        makeTicketBar(playerTicketBar, playerTicketLabel, UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1), false)
        makeTicketBar(enemyTicketBar, enemyTicketLabel, UIColor(red: 0.85, green: 0.2, blue: 0.2, alpha: 1), true)
        updateTicketBars()
    }

    private func updateTicketBars() {
        let pw = 100 * CGFloat(playerTickets) / 100
        for c in playerTicketBar.constraints where c.firstAttribute == .width { c.constant = pw; break }
        playerTicketLabel.text = "\(playerTickets)"
        let ew = 100 * CGFloat(enemyTickets) / 150
        for c in enemyTicketBar.constraints where c.firstAttribute == .width { c.constant = ew; break }
        enemyTicketLabel.text = "\(enemyTickets)"
    }

    private func updateCaptureHUD() {
        for (i, cp) in capturePoints.enumerated() where i < 4 {
            // HUD labels are at tags 300-303
            if let lbl = view.viewWithTag(300 + i) as? UILabel {
                if cp.progress > 0.5 { lbl.textColor = UIColor.green; lbl.backgroundColor = UIColor(red: 0, green: 0.5, blue: 0, alpha: 0.6) }
                else if cp.progress < -0.5 { lbl.textColor = UIColor.red; lbl.backgroundColor = UIColor(red: 0.5, green: 0, blue: 0, alpha: 0.6) }
                else { lbl.textColor = UIColor(white: 0.6, alpha: 1); lbl.backgroundColor = UIColor(white: 0, alpha: 0.4) }
                let pct = Int(abs(cp.progress) * 100)
                lbl.text = "\(cp.label) \(pct)%"
            }
        }
    }

    private func updateMinimap() {
        let sz: CGFloat = 90, halfMap = CGFloat(mapSize/2), scale = sz / CGFloat(mapSize)
        let r = UIGraphicsImageRenderer(size: CGSize(width: sz, height: sz))
        let img = r.image { ctx in
            UIColor(red: 0.4, green: 0.7, blue: 0.25, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: sz, height: sz))
            UIColor(red: 0.55, green: 0.35, blue: 0.15, alpha: 1).setFill()
            for box in barrierBoxes {
                let rx = (CGFloat(box.minX) + halfMap) * scale; let rz = (CGFloat(box.minZ) + halfMap) * scale
                let rw = CGFloat(box.maxX - box.minX) * scale; let rd = CGFloat(box.maxZ - box.minZ) * scale
                ctx.fill(CGRect(x: rx, y: rz, width: rw, height: rd))
            }
            UIColor.gray.setFill()
            let tx = (CGFloat(turretNode.position.x) + halfMap) * scale - 2
            let tz = (CGFloat(turretNode.position.z) + halfMap) * scale - 2
            ctx.fill(CGRect(x: tx, y: tz, width: 4, height: 4))
            for cp in capturePoints {
                let c: UIColor = cp.progress > 0.5 ? .green : (cp.progress < -0.5 ? .red : .white)
                c.setFill()
                let cx = (CGFloat(cp.node.position.x) + halfMap) * scale - 3
                let cz = (CGFloat(cp.node.position.z) + halfMap) * scale - 3
                ctx.fill(CGRect(x: cx, y: cz, width: 6, height: 6))
            }
            UIColor.red.setFill()
            for bot in bots where bot.alive {
                let bx = (CGFloat(bot.node.presentation.position.x) + halfMap) * scale - 1.5
                let bz = (CGFloat(bot.node.presentation.position.z) + halfMap) * scale - 1.5
                ctx.fill(CGRect(x: bx, y: bz, width: 3, height: 3))
            }
            UIColor.white.setFill()
            let px = (CGFloat(cameraHolder.position.x) + halfMap) * scale - 2
            let pz = (CGFloat(cameraHolder.position.z) + halfMap) * scale - 2
            ctx.fill(CGRect(x: px, y: pz, width: 4, height: 4))
        }
        minimapView.layer.contents = img.cgImage
    }

    private func spawnAmmoCrates() {
        let ammoPositions: [(Float, Float)] = [(10, 0), (-5, 8)]
        for (ax, az) in ammoPositions {
            let crate = SCNBox(width: 0.8, height: 0.6, length: 0.6, chamferRadius: 0.02)
            crate.firstMaterial?.diffuse.contents = UIColor(red: 0.6, green: 0.4, blue: 0.1, alpha: 1)
            let crateNode = SCNNode(geometry: crate)
            crateNode.position = SCNVector3(ax, groundTop + 0.3, az)
            crateNode.name = "ammo"
            scene.rootNode.addChildNode(crateNode)
            // 3D label above
            let textGeo = SCNText(string: "🔫", extrusionDepth: 0.02)
            textGeo.font = UIFont.systemFont(ofSize: 0.3)
            textGeo.firstMaterial?.diffuse.contents = UIColor.yellow
            let textNode = SCNNode(geometry: textGeo)
            textNode.position = SCNVector3(ax, groundTop + 0.8, az)
            textNode.scale = SCNVector3(0.3, 0.3, 0.3)
            textNode.constraints = [SCNBillboardConstraint()]
            scene.rootNode.addChildNode(textNode)
        }
    }

    private func spawnTurret() {
        let baseGeo = SCNBox(width: 1.2, height: 0.8, length: 1.2, chamferRadius: 0.04)
        baseGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.35, green: 0.35, blue: 0.4, alpha: 1)
        turretBase.geometry = baseGeo; turretBase.position = SCNVector3(0, groundTop + 0.4, 0)
        turretNode.addChildNode(turretBase)
        
        // Gun barrel
        let gunGeo = SCNCylinder(radius: 0.08, height: 1.2)
        gunGeo.firstMaterial?.diffuse.contents = UIColor.darkGray
        turretGun.geometry = gunGeo; turretGun.eulerAngles.x = Float.pi / 2
        turretGun.position = SCNVector3(0, 0.6, 0.3)
        turretNode.addChildNode(turretGun)
        
        // Shield front
        let shieldGeo = SCNBox(width: 1.0, height: 0.5, length: 0.1, chamferRadius: 0.02)
        shieldGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.35, blue: 0.3, alpha: 1)
        let shield = SCNNode(geometry: shieldGeo); shield.position = SCNVector3(0, 0.2, 0.6)
        turretNode.addChildNode(shield)
        
        turretNode.position = SCNVector3(14, groundTop, 0)
        scene.rootNode.addChildNode(turretNode)
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
        if inTurret {
            guard !isGameOver, !isPaused, turretAmmo > 0, shootCooldown <= 0 else { return }
            turretAmmo -= 1; shootCooldown = 0.1; refreshHUD()
        } else {
            guard !isGameOver, !isReloading, !isPaused, curAmmo > 0, shootCooldown <= 0 else { return }
            let ws = weaponStats()
            curAmmo -= 1; shootCooldown = ws.fireRate; refreshHUD()
        }
        let fwd: SCNVector3
        let spawn: SCNVector3
        if inTurret {
            fwd = worldFront(of: cameraNode.presentation)
            // Find nearest turret for bullet spawn
            var nearest = turretNode
            var minDist: Float = 99
            for t in [turretNode] + cpTurretNodes { let d = dist(cameraHolder.position, t.position); if d < minDist { minDist = d; nearest = t } }
            spawn = scene.rootNode.convertPosition(SCNVector3(0, 0.8, -0.8), from: nearest)
        } else {
            fwd = worldFront(of: cameraNode.presentation)
            spawn = cameraHolder.presentation.convertPosition(SCNVector3(0.15, -0.1, -0.6), to: scene.rootNode)
        }
        let b = SCNSphere(radius: 0.06)
        b.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.9, blue: 0.2, alpha: 1)
        let bn = SCNNode(geometry: b); bn.position = spawn; scene.rootNode.addChildNode(bn)
        let bulletSpd: Float = inTurret ? 70 : weaponStats().bulletSpeed
        bullets.append(Bullet(node: bn, velocity: SCNVector3(fwd.x*bulletSpd, fwd.y*bulletSpd, fwd.z*bulletSpd), lifetime: 0, isBotBullet: false))
        particles(at: spawn, color: UIColor(red: 1, green: 0.9, blue: 0.2, alpha: 1), count: 3)
        weaponNode.position.z = -0.22
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.weaponNode.position.z = -0.3 }
    }
    
    private func throwGrenade() {
        guard !isGameOver, !isPaused, grenadeCount > 0, shootCooldown <= 0 else { return }
        grenadeCount -= 1; shootCooldown = 0.8; refreshHUD()
        let fwd = worldFront(of: cameraNode.presentation)
        let spawn = cameraHolder.presentation.convertPosition(SCNVector3(0.2, 0.1, -0.3), to: scene.rootNode)
        let g = SCNSphere(radius: 0.08)
        g.firstMaterial?.diffuse.contents = UIColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1)
        let gn = SCNNode(geometry: g); gn.position = spawn; scene.rootNode.addChildNode(gn)
        // Arc trajectory: forward + upward
        let vel = SCNVector3(fwd.x*10, 6, fwd.z*10)
        bullets.append(Bullet(node: gn, velocity: vel, lifetime: 0, isBotBullet: false, isGrenade: true))
    }
    
    private func reload() {
        guard !isReloading, curAmmo < curMag, !isGameOver, curReserve > 0 else { return }
        isReloading = true; showMsg("换弹中..."); refreshHUD()
        DispatchQueue.main.asyncAfter(deadline: .now() + weaponStats().reloadTime) { [weak self] in
            guard let s = self else { return }
            let need = s.curMag - s.curAmmo; let take = min(need, s.curReserve)
            s.curAmmo += take; s.curReserve -= take; s.isReloading = false; s.hideMsg(); s.refreshHUD()
        }
    }

    private func replenishAmmo() {
        if inTurret { turretAmmo = min(100, turretAmmo + 50); turretReserve = max(0, turretReserve - 50) }
        else { curAmmo = curMag }
        showMsg("弹药补充!")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.hideMsg() }
        refreshHUD()
    }

    private func reloadTurret() {
        guard !isReloading, turretAmmo < 100, turretReserve > 0 else { return }
        isReloading = true; showMsg("换弹中..."); refreshHUD()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let s = self else { return }
            let need = 100 - s.turretAmmo; let take = min(need, s.turretReserve)
            s.turretAmmo += take; s.turretReserve -= take; s.isReloading = false; s.hideMsg(); s.refreshHUD()
        }
    }
    
    private func botFire(_ bot: Bot) {
        let bp = bot.node.presentation.position
        let head = SCNVector3(bp.x, bp.y + 1.5, bp.z)
        let target = inTurret ? turretNode.position : cameraHolder.presentation.position
        let to = SCNVector3(target.x - head.x, target.y - head.y, target.z - head.z)
        let len = sqrt(to.x*to.x + to.y*to.y + to.z*to.z); guard len > 0 else { return }
        let d = SCNVector3(to.x/len, to.y/len, to.z/len)
        let b = SCNSphere(radius: 0.04)
        b.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.5, blue: 0.2, alpha: 1)
        let bn = SCNNode(geometry: b); bn.position = SCNVector3(head.x+d.x*0.4, head.y+d.y*0.4, head.z+d.z*0.4)
        scene.rootNode.addChildNode(bn)
        bullets.append(Bullet(node: bn, velocity: SCNVector3(d.x*30, d.y*30, d.z*30), lifetime: 0, isBotBullet: true))
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

    private func killBot(_ index: Int) {
        guard index < bots.count, bots[index].alive else { return }
        bots[index].alive = false
        let node = bots[index].node
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.4
        node.eulerAngles.x = Float.pi / 2
        node.position.y -= 0.4
        node.opacity = 0.5
        SCNTransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak node] in node?.removeFromParentNode() }
        kills += 1; score += 100; refreshHUD()
        if kills >= totalBots { score += Int(hp) * 5; refreshHUD(); endGame(won: true) }
    }

    private func hurtPlayer(_ dmg: Float) {
        hp = max(0, hp - dmg); refreshHUD()
        UIView.animate(withDuration: 0.1, animations: { self.view.backgroundColor = UIColor(red: 0.3, green: 0, blue: 0, alpha: 1) }) { _ in
            UIView.animate(withDuration: 0.2) { self.view.backgroundColor = .black }
        }
        if hp <= 0 {
            playerTickets -= 1; updateTicketBars()
            if playerTickets <= 0 { endGame(won: false) }
            else { endGame(won: false) } // Show deploy screen
        }
    }
    
    private func endGame(won: Bool) {
        isGameOver = true; isShooting = false; inTurret = false; turretButton.isHidden = true
        let title = gameOverView.viewWithTag(100) as? UILabel
        let sub = gameOverView.viewWithTag(101) as? UILabel
        let deployLabel = gameOverView.viewWithTag(102)
        // Find class stack (tag 200) and exit button
        let classStack = gameOverView.viewWithTag(200)
        title?.text = won ? "🏆 胜利!" : "💀 阵亡!"
        title?.textColor = won ? UIColor(red: 0.3, green: 0.85, blue: 0.3, alpha: 1) : UIColor(red: 0.95, green: 0.2, blue: 0.2, alpha: 1)
        sub?.text = "击杀: \(kills)/\(totalBots)  得分: \(score)"
        deployLabel?.isHidden = won
        classStack?.isHidden = won
        UIView.animate(withDuration: 0.4) { self.gameOverView.alpha = 1 }
    }
    
    @objc private func exitTap() { dismiss(animated: true) }
    
    // MARK: - HUD
    private func refreshHUD() {
        let r = CGFloat(hp / maxHp)
        for c in healthFill.superview?.constraints ?? [] where c.firstItem === healthFill && c.firstAttribute == .width { c.constant = 166 * r; break }
        healthLabel.text = "❤️ \(Int(hp))"
        let ws = weaponStats(); let resText = currentSlot == .grenade ? "" : "/\(curReserve)"
        ammoLabel.text = inTurret ? (isReloading ? "🔄 ..." : "🔫 \(turretAmmo)/\(turretReserve)") :
            (isReloading ? "🔄 ..." : "\(ws.icon) \(curAmmo)\(resText)")
        killsLabel.text = "💀 \(kills)/\(totalBots)"
        scoreLabel.text = "⭐ \(score)"
        grenadeBtn.setTitle("💣\(grenadeCount)", for: .normal)
    }
    
    private func showMsg(_ t: String) { messageLabel.text = t; UIView.animate(withDuration: 0.2) { self.messageLabel.alpha = 1 } }
    private func hideMsg() { UIView.animate(withDuration: 0.2) { self.messageLabel.alpha = 0 } }
    
    // MARK: - Game Loop
    private func tick() {
        guard !isGameOver, !isPaused else { return }
        let now = CACurrentMediaTime(); let dt = Float(min(now - lastTime, 0.1)); lastTime = now
        shootCooldown = max(0, shootCooldown - TimeInterval(dt))
        healCooldown = max(0, healCooldown - TimeInterval(dt))
        
        // Medic self-heal
        if playerClass == .medic && hp < maxHp && healCooldown <= 0 {
            hp = min(maxHp, hp + 2 * dt); healCooldown = 0.5; refreshHUD()
        }
        
        // Auto-fire for automatic weapons (not grenade)
        if isShooting && shootCooldown <= 0 && !isReloading && currentSlot != .grenade && curAmmo > 0 { tryShoot() }
        
        // Check turret proximity (main + CP turrets)
        if !inTurret {
            var minDist: Float = 99
            for t in [turretNode] + cpTurretNodes { minDist = min(minDist, dist(cameraHolder.position, t.position)) }
            nearTurret = minDist < 2.5
            turretButton.isHidden = !nearTurret
        }
        
        // Jump physics
        if isJumping {
            jumpVelocity -= 25 * dt
            var np = cameraHolder.position
            np.y += jumpVelocity * dt
            if np.y <= playerY { np.y = playerY; isJumping = false; jumpVelocity = 0 }
            if !isInsideBarrier(x: np.x, y: np.y, z: np.z) { cameraHolder.position = np }
        }

        // Move player
        if joystickActive && !inTurret {
            let sp = isSprinting ? moveSpeed * 1.6 : moveSpeed
            var fwd = worldFront(of: cameraNode.presentation); fwd.y = 0
            let fl = sqrt(fwd.x*fwd.x + fwd.z*fwd.z)
            let mf = fl > 0 ? SCNVector3(fwd.x/fl, 0, fwd.z/fl) : SCNVector3(0, 0, -1)
            let rt = SCNVector3(mf.z, 0, -mf.x)
            var np = cameraHolder.position
            np.x += rt.x * Float(moveInput.x) * sp * dt + mf.x * Float(moveInput.y) * sp * dt
            np.z += rt.z * Float(moveInput.x) * sp * dt + mf.z * Float(moveInput.y) * sp * dt
            let half = Float(mapSize/2) - 1.5
            np.x = max(-half, min(half, np.x)); np.z = max(-half, min(half, np.z))
            if !isJumping { np.y = playerY }
            if !isInsideBarrier(x: np.x, y: np.y, z: np.z) { cameraHolder.position = np }
        }
        
        // Turret aim follows camera look
        if inTurret {
            // Find nearest turret and rotate it
            var nearest = turretNode
            var minDist: Float = 99
            for t in [turretNode] + cpTurretNodes { let d = dist(cameraHolder.position, t.position); if d < minDist { minDist = d; nearest = t } }
            nearest.eulerAngles.y = cameraNode.eulerAngles.y
            if turretAmmo <= 0 && turretReserve > 0 { reloadTurret() }
            if isShooting && shootCooldown <= 0 && turretAmmo > 0 { tryShoot() }
        }
        
        // Bullets
        var rmBullets = IndexSet()
        for i in 0..<bullets.count {
            var bl = bullets[i]
            bl.node.position.x += bl.velocity.x * dt; bl.node.position.y += bl.velocity.y * dt; bl.node.position.z += bl.velocity.z * dt
            if bl.isGrenade { bl.velocity.y -= 15 * dt } // gravity
            bl.lifetime += TimeInterval(dt); bullets[i].lifetime = bl.lifetime; bullets[i].node.position = bl.node.position
            
            if bl.lifetime > 3.0 { rmBullets.insert(i); bl.node.removeFromParentNode(); continue }
            if bl.node.position.y <= groundTop {
                if bl.isGrenade { explodeGrenade(at: bl.node.position) }
                else { particles(at: bl.node.position, color: UIColor(white: 0.7, alpha: 1), count: 4) }
                rmBullets.insert(i); bl.node.removeFromParentNode(); continue
            }
            if isInsideBarrier(x: bl.node.position.x, y: bl.node.position.y, z: bl.node.position.z) {
                if bl.isGrenade { explodeGrenade(at: bl.node.position) }
                else { particles(at: bl.node.position, color: UIColor(white: 0.7, alpha: 1), count: 4) }
                rmBullets.insert(i); bl.node.removeFromParentNode(); continue
            }
            
            if bl.isBotBullet {
                let targetY = inTurret ? turretNode.position.y + 1.2 : cameraHolder.position.y
                let targetPos = inTurret ? SCNVector3(turretNode.position.x, targetY, turretNode.position.z) : cameraHolder.position
                if dist(bl.node.position, targetPos) < 0.8 {
                    hurtPlayer(8); particles(at: bl.node.position, color: .red, count: 5)
                    rmBullets.insert(i); bl.node.removeFromParentNode()
                }
            } else {
                let dmg = Float(weaponStats().damage)
                for j in 0..<bots.count where bots[j].alive {
                    let hd = SCNVector3(bots[j].node.presentation.position.x, bots[j].node.presentation.position.y + 1.55, bots[j].node.presentation.position.z)
                    let hitDist: Float = bl.isGrenade ? 3.0 : 0.8
                    if dist(bl.node.position, hd) < hitDist {
                        bots[j].hp -= bl.isGrenade ? dmg : dmg
                        bots[j].hitFlashTimer = 0.15
                        particles(at: bl.node.position, color: .orange, count: bl.isGrenade ? 15 : 8)
                        if !bl.isGrenade { rmBullets.insert(i); bl.node.removeFromParentNode() } else { explodeGrenade(at: bl.node.position); rmBullets.insert(i); bl.node.removeFromParentNode() }
                        if bots[j].hp <= 0 { killBot(j) }
                        break
                    }
                }
            }
        }
        bullets = bullets.enumerated().filter { !rmBullets.contains($0.offset) }.map { $0.element }
        
        // Bots
        for i in 0..<bots.count where bots[i].alive {
            var bt = bots[i]
            // Hit flash
            if bt.hitFlashTimer > 0 { bt.hitFlashTimer -= TimeInterval(dt); bt.node.opacity = bt.hitFlashTimer > 0 ? 0.4 : 1.0 }
            else { bt.node.opacity = 1.0 }
            // Health bar
            let hpRatio = bt.hp / bt.maxHp
            bt.hpBarFill.scale = SCNVector3(hpRatio, 1, 1)
            bt.hpBarFill.geometry?.firstMaterial?.diffuse.contents = hpRatio > 0.5 ? UIColor.green : (hpRatio > 0.25 ? UIColor.yellow : UIColor.red)
            bots[i].hitFlashTimer = bt.hitFlashTimer
            
            let target = inTurret ? turretNode.position : cameraHolder.position
            let to = SCNVector3(target.x - bt.node.position.x, 0, target.z - bt.node.position.z)
            let d = sqrt(to.x*to.x + to.z*to.z)
            bt.node.eulerAngles.y = atan2(to.x, to.z)
            let spd: Float = 2.5; let mv = d > 0 ? SCNVector3(to.x/d, 0, to.z/d) : SCNVector3(0, 0, 1)
            var np = bt.node.position
            if d > 7 { np.x += mv.x * spd * dt; np.z += mv.z * spd * dt }
            else if d < 4 { np.x -= mv.x * spd * 0.5 * dt; np.z -= mv.z * spd * 0.5 * dt }
            else {
                bt.strafeTimer -= TimeInterval(dt)
                if bt.strafeTimer <= 0 { bt.strafeDir = -bt.strafeDir; bt.strafeTimer = TimeInterval.random(in: 1...3) }
                np.x += -mv.z * bt.strafeDir * spd * 0.6 * dt; np.z += mv.x * bt.strafeDir * spd * 0.6 * dt
                bots[i].strafeDir = bt.strafeDir; bots[i].strafeTimer = bt.strafeTimer
            }
            np.y = botFootY
            if !isInsideBarrier(x: np.x, y: np.y, z: np.z) { bt.node.position = np }
            bt.shootTimer -= TimeInterval(dt)
            if bt.shootTimer <= 0 && d < 25 { botFire(bt); bt.shootTimer = TimeInterval.random(in: 0.8...2.5) }
            bots[i].shootTimer = bt.shootTimer
        }
        
        // Ammo crate pickup
        ammoNearTimer = 0
        for child in scene.rootNode.childNodes where child.name == "ammo" {
            let d = dist(cameraHolder.position, child.position)
            if d < 2 { ammoNearTimer += dt; if ammoNearTimer > 1.0 { replenishAmmo(); ammoNearTimer = 0 } }
        }

        weaponNode.position.y = -0.11 + Float(sin(now * (joystickActive ? 8 : 3)) * (joystickActive ? 0.008 : 0.003))

        // Capture points — drain enemy tickets + enable respawn
        for i in 0..<capturePoints.count {
            let cpPos = capturePoints[i].node.position
            let playerDist = dist(SCNVector3(cameraHolder.position.x, 0, cameraHolder.position.z),
                                   SCNVector3(cpPos.x, 0, cpPos.z))
            var delta: Float = 0
            if playerDist < 4 { delta = dt * 0.3 }
            for bot in bots where bot.alive {
                if dist(SCNVector3(bot.node.position.x, 0, bot.node.position.z),
                        SCNVector3(cpPos.x, 0, cpPos.z)) < 4 { delta -= dt * 0.2 }
            }
            capturePoints[i].progress = max(-1, min(1, capturePoints[i].progress + delta))
            // Drain tickets for captured points (use float accumulator to avoid truncation)
            if capturePoints[i].progress > 0.5 {
                ticketDrainAccum += dt * 0.5
                let drain = Int(ticketDrainAccum)
                if drain > 0 { enemyTickets = max(0, enemyTickets - drain); ticketDrainAccum -= Float(drain) }
            }
            if capturePoints[i].progress < -0.5 {
                ticketDrainAccum += dt * 0.4
                let drain = Int(ticketDrainAccum)
                if drain > 0 { playerTickets = max(0, playerTickets - drain); ticketDrainAccum -= Float(drain) }
            }
            // Update flag color
            let p = capturePoints[i].progress
            let flagColor: UIColor
            if p > 0.5 { flagColor = UIColor(red: 0.2, green: 0.7, blue: 0.2, alpha: 1) }
            else if p < -0.5 { flagColor = UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1) }
            else { flagColor = UIColor.white }
            capturePoints[i].flagNode.geometry?.firstMaterial?.diffuse.contents = flagColor
        }
        updateCaptureHUD(); updateTicketBars()
        if enemyTickets <= 0 { endGame(won: true) }
        if playerTickets <= 0 { endGame(won: false) }

        // Bot respawn
        let aliveBots = bots.filter { $0.alive }.count
        if aliveBots < totalBots && enemyTickets > 0 {
            var bx: Int, bz: Int
            repeat {
                bx = Int.random(in: (-mapSize/2+3)...(mapSize/2-4))
                bz = Int.random(in: (-mapSize/2+3)...(mapSize/2-4))
            } while (abs(bx) < 5 && abs(bz) < 5) || isInsideBarrier(x: Float(bx), y: botFootY, z: Float(bz))
            let colors: [UIColor] = [
                UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1), UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1),
                UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1), UIColor(red: 0.7, green: 0.4, blue: 0.1, alpha: 1),
                UIColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1), UIColor(red: 0.1, green: 0.6, blue: 0.7, alpha: 1),
                UIColor(red: 0.8, green: 0.5, blue: 0, alpha: 1),   UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1),
            ]
            let n = makeBot(colors.randomElement()!)
            n.position = SCNVector3(Float(bx), botFootY, Float(bz))
            scene.rootNode.addChildNode(n)
            let hpBg = SCNNode(geometry: { let p = SCNPlane(width: 0.5, height: 0.06); p.firstMaterial?.diffuse.contents = UIColor(white: 0.15, alpha: 1); return p }())
            hpBg.position = SCNVector3(0, 1.9, 0); hpBg.constraints = [SCNBillboardConstraint()]; n.addChildNode(hpBg)
            let hpFill = SCNNode(geometry: { let p = SCNPlane(width: 0.5, height: 0.04); p.firstMaterial?.diffuse.contents = UIColor.green; return p }())
            hpFill.position = SCNVector3(0, 0, 0.01); hpFill.pivot = SCNMatrix4MakeTranslation(-0.25, 0, 0); hpBg.addChildNode(hpFill)
            bots.append(Bot(node: n, hp: 50, maxHp: 50, alive: true,
                shootTimer: TimeInterval.random(in: 1...2.5), strafeDir: Bool.random() ? 1 : -1,
                strafeTimer: TimeInterval.random(in: 1...3), hitFlashTimer: 0, hpBarBg: hpBg, hpBarFill: hpFill))
            enemyTickets = max(0, enemyTickets - 1)
        }

        updateMinimap()
    }
    
    private func explodeGrenade(at pos: SCNVector3) {
        // Spawn visible explosion spheres
        for _ in 0..<20 {
            let g = SCNSphere(radius: 0.1)
            g.firstMaterial?.diffuse.contents = UIColor.orange
            g.firstMaterial?.emission.contents = UIColor(red: 1, green: 0.3, blue: 0, alpha: 1)
            let n = SCNNode(geometry: g)
            n.position = pos
            n.position.x += Float.random(in: -0.5...0.5)
            n.position.z += Float.random(in: -0.5...0.5)
            scene.rootNode.addChildNode(n)
            let moveAction = SCNAction.move(by: SCNVector3(Float.random(in: -4...4), Float.random(in: 2...8), Float.random(in: -4...4)), duration: 0.6)
            let scaleAction = SCNAction.scale(to: 2.5, duration: 0.6)
            let fadeAction = SCNAction.fadeOut(duration: 0.6)
            let removeAction = SCNAction.removeFromParentNode()
            n.runAction(SCNAction.sequence([SCNAction.group([moveAction, scaleAction, fadeAction]), removeAction]))
        }
        // Flash light
        let lightNode = SCNNode()
        lightNode.light = SCNLight(); lightNode.light?.type = .omni
        lightNode.light?.color = UIColor.orange; lightNode.position = SCNVector3(pos.x, pos.y + 1, pos.z)
        scene.rootNode.addChildNode(lightNode)
        lightNode.runAction(SCNAction.sequence([SCNAction.wait(duration: 0.2), SCNAction.removeFromParentNode()]))
        // Damage
        for j in 0..<bots.count where bots[j].alive {
            let bp = bots[j].node.presentation.position
            let d = dist(pos, SCNVector3(bp.x, bp.y + 1.5, bp.z))
            if d < 4 {
                bots[j].hp -= 90 * (1 - d / 4)
                bots[j].hitFlashTimer = 0.2
                if bots[j].hp <= 0 { killBot(j) }
            }
        }
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
        let r: Float = 0.35  // camera collision radius
        let eyeY: Float = playerY
        for box in barrierBoxes {
            // Only collide if camera eye is within barrier height range
            if eyeY < box.minY - 0.2 || eyeY > box.maxY + 0.3 { continue }
            if x + r > box.minX && x - r < box.maxX,
               z + r > box.minZ && z - r < box.maxZ {
                return true
            }
        }
        return false
    }
}
