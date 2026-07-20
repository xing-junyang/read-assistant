import UIKit
import SceneKit

// MARK: - Skill Snake Game View Controller
/// Minecraft-style Snake game with skills using SceneKit (iOS 10+).
/// Portrait-only top-down view. Swipe to control direction. Costs 15 coins per play.
final class SkillSnakeGameViewController: UIViewController {

    // MARK: - Constants
    private let gridCols = 20
    private let gridRows = 30
    private let cellSize: Float = 0.8
    private let tickInterval: TimeInterval = 0.14
    private let skillCooldownBase: TimeInterval = 8.0

    // MARK: - Game State
    private var snake: [(x: Int, y: Int)] = []
    private var dir: (dx: Int, dy: Int) = (1, 0)
    private var nextDir: (dx: Int, dy: Int) = (1, 0)
    private var foodPos: (x: Int, y: Int) = (5, 5)
    private var specialFood: (x: Int, y: Int)? = nil
    private var specialFoodLifetime: Float = 0
    private var score: Int = 0
    private var bestScore: Int = 0
    private var isGameOver = false
    private var isPlaying = false
    private var tickAccum: TimeInterval = 0

    // Skill state
    private struct SkillState {
        var cooldownRemaining: TimeInterval = 0
        var activeRemaining: TimeInterval = 0
        let maxCooldown: TimeInterval
        let maxDuration: TimeInterval
    }
    private var skillSpeed = SkillState(maxCooldown: 8.0, maxDuration: 3.0)
    private var skillShield = SkillState(maxCooldown: 10.0, maxDuration: 4.0)
    private var skillMagnet = SkillState(maxCooldown: 9.0, maxDuration: 4.5)
    private var skillGhost = SkillState(maxCooldown: 12.0, maxDuration: 2.5)

    // MARK: - SceneKit
    private let scnView = SCNView()
    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private var snakeNodes: [SCNNode] = []
    private var foodNode = SCNNode()
    private var specialFoodNode: SCNNode?
    private var gridNodes: [SCNNode] = []

    // MARK: - HUD
    private let scoreLabel = UILabel()
    private let bestLabel = UILabel()
    private let gameOverView = UIView()
    private var skillButtons: [UIButton] = []
    private let skillContainer = UIView()

    // MARK: - Timer
    private var gameTimer: Timer?
    private var lastTickTime: TimeInterval = 0

    // MARK: - Init
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        bestScore = UserDefaults.standard.integer(forKey: "skillSnakeBest")
        buildScene()
        buildFoodNode()
        buildGrid()
        buildHUD()
        buildGameOver()
        buildSkillButtons()
        setupGestures()
        resetGame()
        lastTickTime = CACurrentMediaTime()
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        gameTimer?.invalidate()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    // MARK: - Scene Setup
    private func buildScene() {
        scnView.scene = scene
        scnView.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.13, alpha: 1)
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

        // Top-down camera
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.orthographicScale = 12
        cameraNode.position = SCNVector3(0, 0, 25)
        scene.rootNode.addChildNode(cameraNode)

        // Lighting
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.85, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let dirLight = SCNNode()
        dirLight.light = SCNLight()
        dirLight.light?.type = .directional
        dirLight.light?.color = UIColor(white: 0.6, alpha: 1)
        dirLight.position = SCNVector3(0, 0, 15)
        scene.rootNode.addChildNode(dirLight)

        // Ground plane
        let planeGeo = SCNPlane(width: CGFloat(Float(gridCols) * cellSize + 2), height: CGFloat(Float(gridRows) * cellSize + 2))
        planeGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.12, green: 0.18, blue: 0.12, alpha: 1)
        planeGeo.firstMaterial?.isDoubleSided = true
        let ground = SCNNode(geometry: planeGeo)
        ground.eulerAngles.x = -Float.pi / 2
        ground.position.z = -0.1
        scene.rootNode.addChildNode(ground)
    }

    private func buildGrid() {
        let gridColor = UIColor(white: 0.5, alpha: 0.35)
        let halfW = Float(gridCols) * cellSize / 2
        let halfH = Float(gridRows) * cellSize / 2

        for col in 0...gridCols {
            let x = Float(col) * cellSize - halfW + cellSize / 2
            let lineGeo = SCNBox(width: 0.02, height: CGFloat(Float(gridRows) * cellSize), length: 0.01, chamferRadius: 0)
            lineGeo.firstMaterial?.diffuse.contents = gridColor
            let line = SCNNode(geometry: lineGeo)
            line.position = SCNVector3(x, 0, 0.05)
            scene.rootNode.addChildNode(line)
            gridNodes.append(line)
        }
        for row in 0...gridRows {
            let y = Float(row) * cellSize - halfH + cellSize / 2
            let lineGeo = SCNBox(width: CGFloat(Float(gridCols) * cellSize), height: 0.02, length: 0.01, chamferRadius: 0)
            lineGeo.firstMaterial?.diffuse.contents = gridColor
            let line = SCNNode(geometry: lineGeo)
            line.position = SCNVector3(0, y, 0.05)
            scene.rootNode.addChildNode(line)
            gridNodes.append(line)
        }

        // Boundary walls
        let wallMat = SCNMaterial()
        wallMat.diffuse.contents = UIColor(red: 0.8, green: 0.3, blue: 0.3, alpha: 0.8)
        let wallThickness: CGFloat = 0.15
        let wallHeight: CGFloat = 0.4
        let totalW = CGFloat(Float(gridCols) * cellSize)
        let totalH = CGFloat(Float(gridRows) * cellSize)

        // Top wall
        let topWallGeo = SCNBox(width: totalW + wallThickness * 2, height: wallHeight, length: wallThickness, chamferRadius: 0.02)
        topWallGeo.materials = [wallMat]
        let topWall = SCNNode(geometry: topWallGeo)
        topWall.position = SCNVector3(0, halfH + cellSize / 2, 0.2)
        scene.rootNode.addChildNode(topWall)
        gridNodes.append(topWall)

        // Bottom wall
        let bottomWallGeo = SCNBox(width: totalW + wallThickness * 2, height: wallHeight, length: wallThickness, chamferRadius: 0.02)
        bottomWallGeo.materials = [wallMat]
        let bottomWall = SCNNode(geometry: bottomWallGeo)
        bottomWall.position = SCNVector3(0, -halfH - cellSize / 2, 0.2)
        scene.rootNode.addChildNode(bottomWall)
        gridNodes.append(bottomWall)

        // Left wall
        let leftWallGeo = SCNBox(width: wallHeight, height: totalH, length: wallThickness, chamferRadius: 0.02)
        leftWallGeo.materials = [wallMat]
        let leftWall = SCNNode(geometry: leftWallGeo)
        leftWall.position = SCNVector3(-halfW - cellSize / 2, 0, 0.2)
        scene.rootNode.addChildNode(leftWall)
        gridNodes.append(leftWall)

        // Right wall
        let rightWallGeo = SCNBox(width: wallHeight, height: totalH, length: wallThickness, chamferRadius: 0.02)
        rightWallGeo.materials = [wallMat]
        let rightWall = SCNNode(geometry: rightWallGeo)
        rightWall.position = SCNVector3(halfW + cellSize / 2, 0, 0.2)
        scene.rootNode.addChildNode(rightWall)
        gridNodes.append(rightWall)
    }

    private func buildFoodNode() {
        let foodGeo = SCNBox(width: CGFloat(cellSize * 0.6), height: CGFloat(cellSize * 0.6), length: 0.3, chamferRadius: 0.08)
        foodGeo.firstMaterial?.diffuse.contents = UIColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1)
        foodNode = SCNNode(geometry: foodGeo)
        foodNode.position.z = 0.15
        scene.rootNode.addChildNode(foodNode)
    }

    private func gridToWorld(_ pos: (x: Int, y: Int)) -> SCNVector3 {
        let halfW = Float(gridCols) * cellSize / 2
        let halfH = Float(gridRows) * cellSize / 2
        return SCNVector3(
            Float(pos.x) * cellSize - halfW + cellSize / 2,
            Float(pos.y) * cellSize - halfH + cellSize / 2,
            0.15
        )
    }

    // MARK: - Snake Nodes
    private func createSnakeSegment(at pos: (x: Int, y: Int), isHead: Bool, index: Int) -> SCNNode {
        let alpha: CGFloat = isHead ? 1.0 : max(0.3, 1.0 - CGFloat(index) / CGFloat(max(snake.count, 1)) * 0.5)
        let color: UIColor
        if isHead {
            if skillShield.activeRemaining > 0 {
                color = UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: alpha)
            } else {
                color = UIColor(red: 0.2, green: 0.75, blue: 0.3, alpha: alpha)
            }
        } else {
            color = UIColor(red: 0.15, green: 0.6, blue: 0.2, alpha: alpha)
        }
        let geo = SCNBox(width: CGFloat(cellSize * 0.75), height: CGFloat(cellSize * 0.75), length: 0.25, chamferRadius: 0.06)
        geo.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry: geo)
        node.position = gridToWorld(pos)

        // Eyes for head
        if isHead {
            let eyeGeo = SCNBox(width: 0.08, height: 0.08, length: 0.02, chamferRadius: 0)
            eyeGeo.firstMaterial?.diffuse.contents = UIColor.white
            let eyeL = SCNNode(geometry: eyeGeo)
            let eyeR = SCNNode(geometry: eyeGeo)
            let pupilGeo = SCNBox(width: 0.04, height: 0.04, length: 0.01, chamferRadius: 0)
            pupilGeo.firstMaterial?.diffuse.contents = UIColor.black
            let pupilL = SCNNode(geometry: pupilGeo)
            let pupilR = SCNNode(geometry: pupilGeo)

            switch (dir.dx, dir.dy) {
            case (1, 0):  // right
                eyeL.position = SCNVector3(0.12, 0.1, 0.13)
                eyeR.position = SCNVector3(0.12, -0.1, 0.13)
                pupilL.position = SCNVector3(0.16, 0.1, 0.14)
                pupilR.position = SCNVector3(0.16, -0.1, 0.14)
            case (-1, 0): // left
                eyeL.position = SCNVector3(-0.12, 0.1, 0.13)
                eyeR.position = SCNVector3(-0.12, -0.1, 0.13)
                pupilL.position = SCNVector3(-0.16, 0.1, 0.14)
                pupilR.position = SCNVector3(-0.16, -0.1, 0.14)
            case (0, 1):  // up
                eyeL.position = SCNVector3(0.1, 0.12, 0.13)
                eyeR.position = SCNVector3(-0.1, 0.12, 0.13)
                pupilL.position = SCNVector3(0.1, 0.16, 0.14)
                pupilR.position = SCNVector3(-0.1, 0.16, 0.14)
            default:      // down
                eyeL.position = SCNVector3(0.1, -0.12, 0.13)
                eyeR.position = SCNVector3(-0.1, -0.12, 0.13)
                pupilL.position = SCNVector3(0.1, -0.16, 0.14)
                pupilR.position = SCNVector3(-0.1, -0.16, 0.14)
            }
            node.addChildNode(eyeL)
            node.addChildNode(eyeR)
            node.addChildNode(pupilL)
            node.addChildNode(pupilR)
        }
        return node
    }

    private func rebuildSnakeNodes() {
        for node in snakeNodes { node.removeFromParentNode() }
        snakeNodes.removeAll()
        for (i, pos) in snake.enumerated() {
            let node = createSnakeSegment(at: pos, isHead: i == 0, index: i)
            if skillGhost.activeRemaining > 0 {
                node.opacity = 0.5
            }
            scene.rootNode.addChildNode(node)
            snakeNodes.append(node)
        }
    }

    // MARK: - Food
    private func spawnFood() {
        var pos: (x: Int, y: Int)
        repeat {
            pos = (Int(arc4random_uniform(UInt32(gridCols))), Int(arc4random_uniform(UInt32(gridRows))))
        } while snake.contains(where: { $0.x == pos.x && $0.y == pos.y })
            || (specialFood?.x == pos.x && specialFood?.y == pos.y)
        foodPos = pos
        foodNode.position = gridToWorld(pos)
        foodNode.isHidden = false

        // Pulse animation
        let pulse = SCNAction.sequence([
            SCNAction.scale(to: 1.15, duration: 0.3),
            SCNAction.scale(to: 1.0, duration: 0.3)
        ])
        foodNode.runAction(SCNAction.repeatForever(pulse), forKey: "pulse")
    }

    private func trySpawnSpecialFood() {
        if specialFood != nil { return }
        if Float(arc4random_uniform(1000)) / 1000.0 < 0.008 {
            var pos: (x: Int, y: Int)
            repeat {
                pos = (Int(arc4random_uniform(UInt32(gridCols))), Int(arc4random_uniform(UInt32(gridRows))))
            } while snake.contains(where: { $0.x == pos.x && $0.y == pos.y })
                || (foodPos.x == pos.x && foodPos.y == pos.y)
            specialFood = pos
            specialFoodLifetime = 10.0

            let geo = SCNSphere(radius: CGFloat(cellSize * 0.35))
            geo.firstMaterial?.diffuse.contents = UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1)
            let node = SCNNode(geometry: geo)
            node.position = gridToWorld(pos)
            node.position.z = 0.2
            scene.rootNode.addChildNode(node)
            specialFoodNode = node

            // Glow
            let glow = SCNAction.sequence([
                SCNAction.scale(to: 1.3, duration: 0.5),
                SCNAction.scale(to: 0.9, duration: 0.5)
            ])
            node.runAction(SCNAction.repeatForever(glow), forKey: "glow")
        }
    }

    // MARK: - HUD
    private func buildHUD() {
        // Score bar
        let barView = UIView()
        barView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        barView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(barView)

        scoreLabel.font = UIFont(name: "AvenirNext-Bold", size: 22) ?? UIFont.boldSystemFont(ofSize: 22)
        scoreLabel.textColor = .white
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        barView.addSubview(scoreLabel)

        bestLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        bestLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        bestLabel.translatesAutoresizingMaskIntoConstraints = false
        barView.addSubview(bestLabel)

        // Close button
        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("✕", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        closeBtn.addTarget(self, action: #selector(closeGame), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        barView.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            barView.topAnchor.constraint(equalTo: view.topAnchor),
            barView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            barView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barView.heightAnchor.constraint(equalToConstant: 44),

            closeBtn.trailingAnchor.constraint(equalTo: barView.trailingAnchor, constant: -12),
            closeBtn.centerYAnchor.constraint(equalTo: barView.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 36),
            closeBtn.heightAnchor.constraint(equalToConstant: 36),

            scoreLabel.leadingAnchor.constraint(equalTo: barView.leadingAnchor, constant: 16),
            scoreLabel.centerYAnchor.constraint(equalTo: barView.centerYAnchor, constant: -4),
            bestLabel.leadingAnchor.constraint(equalTo: scoreLabel.trailingAnchor, constant: 12),
            bestLabel.centerYAnchor.constraint(equalTo: barView.centerYAnchor, constant: 4)
        ])
    }

    private func buildSkillButtons() {
        let skills: [(String, String)] = [
            ("⚡ 加速", "skill_speed"),
            ("🛡️ 护盾", "skill_shield"),
            ("🧲 磁铁", "skill_magnet"),
            ("👻 穿墙", "skill_ghost")
        ]

        skillContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(skillContainer)
        NSLayoutConstraint.activate([
            skillContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            skillContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            skillContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            skillContainer.heightAnchor.constraint(equalToConstant: 80)
        ])

        for (i, (title, tag)) in skills.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.setTitleColor(.white, for: .normal)
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .bold)
            btn.backgroundColor = UIColor(white: 0.2, alpha: 0.9)
            btn.layer.cornerRadius = 10
            btn.layer.borderWidth = 1
            btn.layer.borderColor = UIColor(white: 0.4, alpha: 1).cgColor
            btn.tag = i
            btn.addTarget(self, action: #selector(skillButtonTapped(_:)), for: .touchUpInside)
            btn.translatesAutoresizingMaskIntoConstraints = false
            skillContainer.addSubview(btn)
            skillButtons.append(btn)
        }

        // Distribute evenly
        for (i, btn) in skillButtons.enumerated() {
            btn.translatesAutoresizingMaskIntoConstraints = false
            if i == 0 {
                btn.leadingAnchor.constraint(equalTo: skillContainer.leadingAnchor).isActive = true
            } else {
                btn.leadingAnchor.constraint(equalTo: skillButtons[i - 1].trailingAnchor, constant: 6).isActive = true
                btn.widthAnchor.constraint(equalTo: skillButtons[i - 1].widthAnchor).isActive = true
            }
            if i == skillButtons.count - 1 {
                btn.trailingAnchor.constraint(equalTo: skillContainer.trailingAnchor).isActive = true
            }
            btn.topAnchor.constraint(equalTo: skillContainer.topAnchor).isActive = true
            btn.bottomAnchor.constraint(equalTo: skillContainer.bottomAnchor).isActive = true
        }
    }

    private func buildGameOver() {
        gameOverView.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        gameOverView.translatesAutoresizingMaskIntoConstraints = false
        gameOverView.isHidden = true
        view.addSubview(gameOverView)
        NSLayoutConstraint.activate([
            gameOverView.topAnchor.constraint(equalTo: view.topAnchor),
            gameOverView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gameOverView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gameOverView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let titleLabel = UILabel()
        titleLabel.font = UIFont(name: "AvenirNext-Bold", size: 36) ?? UIFont.boldSystemFont(ofSize: 36)
        titleLabel.text = "游戏结束"
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        gameOverView.addSubview(titleLabel)

        let finalScoreLabel = UILabel()
        finalScoreLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        finalScoreLabel.textColor = .white
        finalScoreLabel.textAlignment = .center
        finalScoreLabel.tag = 100
        finalScoreLabel.translatesAutoresizingMaskIntoConstraints = false
        gameOverView.addSubview(finalScoreLabel)

        let restartLabel = UILabel()
        restartLabel.font = UIFont.systemFont(ofSize: 17)
        restartLabel.text = "点击屏幕重新开始"
        restartLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        restartLabel.textAlignment = .center
        restartLabel.translatesAutoresizingMaskIntoConstraints = false
        gameOverView.addSubview(restartLabel)

        // Close button on game over
        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("✕ 关闭", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        closeBtn.backgroundColor = UIColor.red.withAlphaComponent(0.7)
        closeBtn.layer.cornerRadius = 8
        closeBtn.addTarget(self, action: #selector(closeGame), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        gameOverView.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: gameOverView.centerYAnchor, constant: -30),
            finalScoreLabel.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            finalScoreLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            restartLabel.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            restartLabel.topAnchor.constraint(equalTo: finalScoreLabel.bottomAnchor, constant: 14),
            closeBtn.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            closeBtn.topAnchor.constraint(equalTo: restartLabel.bottomAnchor, constant: 20),
            closeBtn.widthAnchor.constraint(equalToConstant: 100),
            closeBtn.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    // MARK: - Gestures
    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        scnView.addGestureRecognizer(tap)
        let swipe = UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipe.maximumNumberOfTouches = 1
        scnView.addGestureRecognizer(swipe)
    }

    @objc private func handleTap() {
        if isGameOver {
            resetGame()
        }
    }

    private var swipeStart: CGPoint = .zero
    @objc private func handleSwipe(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            swipeStart = pan.location(in: scnView)
        case .ended:
            let end = pan.location(in: scnView)
            let dx = end.x - swipeStart.x
            let dy = end.y - swipeStart.y
            if abs(dx) < 10 && abs(dy) < 10 { return }
            if isGameOver { resetGame(); return }
            if !isPlaying { isPlaying = true }
            if abs(dx) > abs(dy) {
                setDirection(dx: dx > 0 ? 1 : -1, dy: 0)
            } else {
                setDirection(dx: 0, dy: dy > 0 ? -1 : 1)
            }
        default: break
        }
    }

    private func setDirection(dx: Int, dy: Int) {
        if dir.dx == -dx && dir.dy == -dy { return }
        nextDir = (dx, dy)
    }

    @objc private func skillButtonTapped(_ sender: UIButton) {
        guard isPlaying, !isGameOver else { return }
        switch sender.tag {
        case 0: activateSkill(skillSpeed) { self.skillSpeed = $0 }
        case 1: activateSkill(skillShield) { self.skillShield = $0 }
        case 2: activateSkill(skillMagnet) { self.skillMagnet = $0 }
        case 3: activateSkill(skillGhost) { self.skillGhost = $0 }
        default: break
        }
    }

    private func activateSkill(_ skill: SkillState, setter: (SkillState) -> Void) {
        var s = skill
        if s.cooldownRemaining > 0 || s.activeRemaining > 0 { return }
        s.activeRemaining = s.maxDuration
        s.cooldownRemaining = s.maxCooldown
        setter(s)
    }

    @objc private func closeGame() {
        dismiss(animated: true)
    }

    // MARK: - Game Loop
    private func resetGame() {
        let startX = gridCols / 2
        let startY = gridRows / 2
        snake = [(startX, startY), (startX - 1, startY), (startX - 2, startY)]
        dir = (1, 0)
        nextDir = (1, 0)
        score = 0
        isGameOver = false
        isPlaying = false
        tickAccum = 0
        specialFood = nil
        specialFoodLifetime = 0
        specialFoodNode?.removeFromParentNode()
        specialFoodNode = nil
        skillSpeed.cooldownRemaining = 0; skillSpeed.activeRemaining = 0
        skillShield.cooldownRemaining = 0; skillShield.activeRemaining = 0
        skillMagnet.cooldownRemaining = 0; skillMagnet.activeRemaining = 0
        skillGhost.cooldownRemaining = 0; skillGhost.activeRemaining = 0

        spawnFood()
        rebuildSnakeNodes()
        updateHUD()
        updateSkillButtons()
        gameOverView.isHidden = true
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = now - lastTickTime
        lastTickTime = now

        if isGameOver { return }

        // Update skill timers
        updateSkill(&skillSpeed, dt: dt)
        updateSkill(&skillShield, dt: dt)
        updateSkill(&skillMagnet, dt: dt)
        updateSkill(&skillGhost, dt: dt)

        // Special food lifetime
        if specialFood != nil {
            specialFoodLifetime -= Float(dt)
            if specialFoodLifetime <= 0 {
                specialFoodNode?.removeFromParentNode()
                specialFoodNode = nil
                specialFood = nil
            }
        }

        // Rotate special food
        specialFoodNode?.eulerAngles.y += Float(dt) * 3

        if !isPlaying { return }

        tickAccum += dt
        if tickAccum < tickInterval { return }
        tickAccum -= tickInterval

        // Apply direction
        dir = nextDir
        var head = snake[0]
        head.x += dir.dx
        head.y += dir.dy

        // Ghost: wrap
        if skillGhost.activeRemaining > 0 {
            if head.x < 0 { head.x = gridCols - 1 }
            if head.x >= gridCols { head.x = 0 }
            if head.y < 0 { head.y = gridRows - 1 }
            if head.y >= gridRows { head.y = 0 }
        }

        // Wall collision
        if head.x < 0 || head.x >= gridCols || head.y < 0 || head.y >= gridRows {
            if skillShield.activeRemaining > 0 {
                skillShield.activeRemaining = 0
                head = snake[0]
            } else {
                endGame()
                return
            }
        }

        // Self collision
        if snake.contains(where: { $0.x == head.x && $0.y == head.y }) {
            if skillShield.activeRemaining > 0 {
                skillShield.activeRemaining = 0
                head = snake[0]
            } else {
                endGame()
                return
            }
        }

        snake.insert(head, at: 0)

        // Eat check
        if head.x == foodPos.x && head.y == foodPos.y {
            score += 10
            spawnFood()
        } else if let sf = specialFood, head.x == sf.x && head.y == sf.y {
            score += 50
            specialFoodNode?.removeFromParentNode()
            specialFoodNode = nil
            specialFood = nil
            specialFoodLifetime = 0
        } else {
            snake.removeLast()
        }

        // Magnet: pull food
        if skillMagnet.activeRemaining > 0 {
            pullFoodTowards(head: snake[0])
        }

        rebuildSnakeNodes()
        updateHUD()
        updateSkillButtons()
        trySpawnSpecialFood()
    }

    private func pullFoodTowards(head: (x: Int, y: Int)) {
        let pullRange = 3
        if abs(head.x - foodPos.x) <= pullRange && abs(head.y - foodPos.y) <= pullRange {
            if head.x < foodPos.x { foodPos.x -= 1 }
            if head.x > foodPos.x { foodPos.x += 1 }
            if head.y < foodPos.y { foodPos.y -= 1 }
            if head.y > foodPos.y { foodPos.y += 1 }
            foodNode.removeAction(forKey: "pulse")
            foodNode.position = gridToWorld(foodPos)
        }
        if let sf = specialFood {
            if abs(head.x - sf.x) <= pullRange && abs(head.y - sf.y) <= pullRange {
                var newSf = sf
                if head.x < newSf.x { newSf.x -= 1 }
                if head.x > newSf.x { newSf.x += 1 }
                if head.y < newSf.y { newSf.y -= 1 }
                if head.y > newSf.y { newSf.y += 1 }
                specialFood = newSf
                specialFoodNode?.position = gridToWorld(newSf)
            }
        }
    }

    private func updateSkill(_ skill: inout SkillState, dt: TimeInterval) {
        if skill.activeRemaining > 0 {
            skill.activeRemaining -= dt
            if skill.activeRemaining < 0 { skill.activeRemaining = 0 }
        }
        if skill.cooldownRemaining > 0 {
            skill.cooldownRemaining -= dt
            if skill.cooldownRemaining < 0 { skill.cooldownRemaining = 0 }
        }
    }

    private func endGame() {
        isGameOver = true
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: "skillSnakeBest")
        }
        if let label = gameOverView.viewWithTag(100) as? UILabel {
            label.text = "得分: \(score)  最高: \(bestScore)"
        }
        gameOverView.isHidden = false
    }

    private func updateHUD() {
        scoreLabel.text = "🐍 \(score)"
        bestLabel.text = "最高: \(bestScore)"
    }

    private func updateSkillButtons() {
        let skills = [skillSpeed, skillShield, skillMagnet, skillGhost]
        let colors: [(UIColor, UIColor)] = [
            (UIColor(red: 1.0, green: 0.92, blue: 0.0, alpha: 1), UIColor(red: 0.6, green: 0.55, blue: 0.0, alpha: 1)),
            (UIColor(red: 0.2, green: 0.5, blue: 0.95, alpha: 1), UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1)),
            (UIColor(red: 1.0, green: 0.35, blue: 0.15, alpha: 1), UIColor(red: 0.6, green: 0.2, blue: 0.1, alpha: 1)),
            (UIColor(red: 0.55, green: 0.15, blue: 0.7, alpha: 1), UIColor(red: 0.35, green: 0.1, blue: 0.45, alpha: 1))
        ]
        for (i, btn) in skillButtons.enumerated() {
            let s = skills[i]
            if s.activeRemaining > 0 {
                btn.backgroundColor = colors[i].0.withAlphaComponent(0.8)
                btn.setTitleColor(.white, for: .normal)
                btn.setTitle("\(btn.titleLabel?.text?.components(separatedBy: " ").first ?? "") 激活", for: .normal)
                btn.layer.borderColor = colors[i].0.cgColor
            } else if s.cooldownRemaining > 0 {
                btn.backgroundColor = UIColor(white: 0.15, alpha: 0.9)
                btn.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .normal)
                let cd = Int(ceil(s.cooldownRemaining))
                btn.setTitle("\(btn.titleLabel?.text?.components(separatedBy: " ").first ?? "") CD\(cd)s", for: .normal)
                btn.layer.borderColor = UIColor(white: 0.3, alpha: 1).cgColor
            } else {
                btn.backgroundColor = colors[i].1.withAlphaComponent(0.8)
                btn.setTitleColor(.white, for: .normal)
                let names = ["⚡ 加速", "🛡️ 护盾", "🧲 磁铁", "👻 穿墙"]
                btn.setTitle(names[i], for: .normal)
                btn.layer.borderColor = colors[i].0.cgColor
            }
        }
    }
}
