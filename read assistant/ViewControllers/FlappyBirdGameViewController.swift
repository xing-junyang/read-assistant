import UIKit
import SceneKit

// MARK: - Flappy Bird Game View Controller
/// Minecraft-style Flappy Bird using SceneKit (iOS 10+).
/// Portrait-only. Tap to flap the bird through pipes. Costs 10 coins per play.
final class FlappyBirdGameViewController: UIViewController {

    // MARK: - Constants
    private let pipeWidth: Float = 1.5
    private let pipeGap: Float = 4.5
    private let pipeSpeed: Float = 2.8
    private let spawnInterval: Float = 2.0
    private let gravity: Float = 11.0
    private let flapForce: Float = 6.0
    private let worldHalfW: Float = 9
    private let worldHalfH: Float = 14

    // MARK: - Game State
    private var birdY: Float = 0
    private var birdVelocityY: Float = 0
    private var score: Int = 0
    private var bestScore: Int = 0
    private var isGameOver = false
    private var isPlaying = false
    private var spawnTimer: Float = 0
    private var pipeNodes: [(top: SCNNode, bottom: SCNNode, passed: Bool)] = []
    private var birdRotation: Float = 0

    // MARK: - SceneKit
    private let scnView = SCNView()
    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let birdNode = SCNNode()
    private let birdBody = SCNNode()
    private let birdWingL = SCNNode()
    private let birdWingR = SCNNode()
    private var wingPhase: Float = 0
    private var gameTimer: Timer?

    // MARK: - HUD
    private let scoreLabel = UILabel()
    private let bestLabel = UILabel()
    private let gameOverView = UIView()

    // MARK: - Init
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        bestScore = UserDefaults.standard.integer(forKey: "flappyBirdBest")
        buildScene()
        buildBird()
        buildDecorations()
        buildHUD()
        buildGameOver()
        setupGestures()
        resetGame()
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
        scnView.backgroundColor = UIColor(red: 0.31, green: 0.73, blue: 0.84, alpha: 1)
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

        // Orthographic camera for 2D side-scroller feel
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.orthographicScale = 12
        cameraNode.position = SCNVector3(0, 0, 20)
        scene.rootNode.addChildNode(cameraNode)

        // Lighting
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.85, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        // Ground
        let groundGeo = SCNBox(width: CGFloat(worldHalfW * 4), height: 2, length: 0.2, chamferRadius: 0.1)
        let groundMat = SCNMaterial()
        groundMat.diffuse.contents = UIColor(red: 0.45, green: 0.78, blue: 0.35, alpha: 1)
        groundGeo.materials = [groundMat]
        let ground = SCNNode(geometry: groundGeo)
        ground.position = SCNVector3(0, -worldHalfH - 1, 0)
        scene.rootNode.addChildNode(ground)

        // Top grass strip
        let topStripGeo = SCNBox(width: CGFloat(worldHalfW * 4), height: 0.3, length: 0.22, chamferRadius: 0)
        topStripGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.2, green: 0.6, blue: 0.2, alpha: 1)
        let topStrip = SCNNode(geometry: topStripGeo)
        topStrip.position = SCNVector3(0, -worldHalfH, 0.01)
        scene.rootNode.addChildNode(topStrip)

        // Ceiling
        let ceilingGeo = SCNBox(width: CGFloat(worldHalfW * 4), height: 1, length: 0.2, chamferRadius: 0)
        ceilingGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1)
        let ceiling = SCNNode(geometry: ceilingGeo)
        ceiling.position = SCNVector3(0, worldHalfH + 0.5, 0)
        scene.rootNode.addChildNode(ceiling)
    }

    private func buildDecorations() {
        // Clouds
        for i in 0..<6 {
            let cloud = buildCloud()
            cloud.position = SCNVector3(Float(i) * 6 - 15, Float.random(in: 5...12), -3)
            scene.rootNode.addChildNode(cloud)
        }
    }

    private func buildCloud() -> SCNNode {
        let node = SCNNode()
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(white: 0.95, alpha: 1)
        for (dx, dy, sz) in [(0, 0, 0.9), (0.7, 0.15, 0.65), (-0.7, -0.1, 0.7), (0.35, 0.5, 0.5), (-0.35, -0.4, 0.55)] {
            let box = SCNBox(width: sz, height: sz * 0.5, length: 0.1, chamferRadius: 0.15)
            box.materials = [mat]
            let part = SCNNode(geometry: box)
            part.position = SCNVector3(Float(dx), Float(dy), 0)
            node.addChildNode(part)
        }
        return node
    }

    // MARK: - Bird (Minecraft Style)
    private func buildBird() {
        birdNode.position = SCNVector3(-5, 0, 0)
        scene.rootNode.addChildNode(birdNode)

        // Body
        let bodyGeo = SCNBox(width: 0.8, height: 0.7, length: 0.55, chamferRadius: 0.05)
        bodyGeo.firstMaterial?.diffuse.contents = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1)
        birdBody.geometry = bodyGeo
        birdNode.addChildNode(birdBody)

        // Eyes
        let eyeGeo = SCNBox(width: 0.14, height: 0.14, length: 0.01, chamferRadius: 0)
        eyeGeo.firstMaterial?.diffuse.contents = UIColor.black
        let leftEye = SCNNode(geometry: eyeGeo)
        leftEye.position = SCNVector3(-0.14, 0.1, 0.28)
        birdBody.addChildNode(leftEye)
        let rightEye = SCNNode(geometry: eyeGeo)
        rightEye.position = SCNVector3(0.14, 0.1, 0.28)
        birdBody.addChildNode(rightEye)

        // Beak
        let beakGeo = SCNBox(width: 0.25, height: 0.12, length: 0.2, chamferRadius: 0.02)
        beakGeo.firstMaterial?.diffuse.contents = UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1)
        let beak = SCNNode(geometry: beakGeo)
        beak.position = SCNVector3(0, -0.05, 0.35)
        birdBody.addChildNode(beak)

        // Wings
        let wingMat = SCNMaterial()
        wingMat.diffuse.contents = UIColor(red: 0.9, green: 0.72, blue: 0.0, alpha: 1)
        let wingGeo = SCNBox(width: 0.75, height: 0.14, length: 0.2, chamferRadius: 0.03)
        wingGeo.materials = [wingMat]
        birdWingL.geometry = wingGeo
        birdWingL.position = SCNVector3(-0.55, 0.05, 0)
        birdBody.addChildNode(birdWingL)
        birdWingR.geometry = wingGeo.copy() as? SCNGeometry
        birdWingR.geometry?.materials = [wingMat]
        birdWingR.position = SCNVector3(0.55, 0.05, 0)
        birdBody.addChildNode(birdWingR)

        // Tail
        let tailGeo = SCNBox(width: 0.2, height: 0.12, length: 0.3, chamferRadius: 0.02)
        tailGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.75, green: 0.55, blue: 0.0, alpha: 1)
        let tail = SCNNode(geometry: tailGeo)
        tail.position = SCNVector3(0, 0, -0.38)
        birdBody.addChildNode(tail)

        // Feet (small blocks below)
        let footGeo = SCNBox(width: 0.12, height: 0.2, length: 0.18, chamferRadius: 0.02)
        footGeo.firstMaterial?.diffuse.contents = UIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1)
        let leftFoot = SCNNode(geometry: footGeo)
        leftFoot.position = SCNVector3(-0.2, -0.45, 0.05)
        birdBody.addChildNode(leftFoot)
        let rightFoot = SCNNode(geometry: footGeo)
        rightFoot.position = SCNVector3(0.2, -0.45, 0.05)
        birdBody.addChildNode(rightFoot)
    }

    // MARK: - Pipes
    private func spawnPipe() {
        let gapCenter = Float.random(in: -8...8)
        let topHeight = gapCenter + pipeGap / 2
        let bottomHeight = gapCenter - pipeGap / 2

        let pipeColor = UIColor(red: 0.15, green: 0.65, blue: 0.2, alpha: 1)
        let capColor = UIColor(red: 0.18, green: 0.72, blue: 0.22, alpha: 1)

        // Top pipe body
        let topBodyH = worldHalfH - topHeight
        let topPipeGeo = SCNBox(width: CGFloat(pipeWidth), height: CGFloat(max(topBodyH, 0.1)), length: 0.3, chamferRadius: 0.05)
        topPipeGeo.firstMaterial?.diffuse.contents = pipeColor
        let topPipe = SCNNode(geometry: topPipeGeo)
        topPipe.position = SCNVector3(worldHalfW + 1, topHeight + topBodyH / 2, 0)

        // Top cap
        let capGeo = SCNBox(width: CGFloat(pipeWidth + 0.3), height: 0.3, length: 0.35, chamferRadius: 0.04)
        capGeo.firstMaterial?.diffuse.contents = capColor
        let topCap = SCNNode(geometry: capGeo)
        topCap.position = SCNVector3(0, -topBodyH / 2, 0)
        topPipe.addChildNode(topCap)

        scene.rootNode.addChildNode(topPipe)

        // Bottom pipe body
        let bottomBodyH = worldHalfH + bottomHeight
        let bottomPipeGeo = SCNBox(width: CGFloat(pipeWidth), height: CGFloat(max(bottomBodyH, 0.1)), length: 0.3, chamferRadius: 0.05)
        bottomPipeGeo.firstMaterial?.diffuse.contents = pipeColor
        let bottomPipe = SCNNode(geometry: bottomPipeGeo)
        bottomPipe.position = SCNVector3(worldHalfW + 1, bottomHeight - bottomBodyH / 2, 0)

        // Bottom cap
        let bottomCapGeo = SCNBox(width: CGFloat(pipeWidth + 0.3), height: 0.3, length: 0.35, chamferRadius: 0.04)
        bottomCapGeo.firstMaterial?.diffuse.contents = capColor
        let bottomCap = SCNNode(geometry: bottomCapGeo)
        bottomCap.position = SCNVector3(0, bottomBodyH / 2, 0)
        bottomPipe.addChildNode(bottomCap)

        scene.rootNode.addChildNode(bottomPipe)

        pipeNodes.append((top: topPipe, bottom: bottomPipe, passed: false))
    }

    // MARK: - HUD
    private func buildHUD() {
        scoreLabel.font = UIFont(name: "AvenirNext-Bold", size: 48) ?? UIFont.boldSystemFont(ofSize: 48)
        scoreLabel.textColor = .white
        scoreLabel.textAlignment = .center
        scoreLabel.layer.shadowColor = UIColor.black.cgColor
        scoreLabel.layer.shadowOffset = CGSize(width: 2, height: 2)
        scoreLabel.layer.shadowOpacity = 0.5
        scoreLabel.layer.shadowRadius = 2
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scoreLabel)

        bestLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        bestLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        bestLabel.textAlignment = .center
        bestLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bestLabel)

        // Close button
        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("✕ 关闭", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        closeBtn.layer.cornerRadius = 8
        closeBtn.addTarget(self, action: #selector(closeGame), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            scoreLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scoreLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 50),
            bestLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bestLabel.topAnchor.constraint(equalTo: scoreLabel.bottomAnchor, constant: 4),
            closeBtn.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            closeBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeBtn.widthAnchor.constraint(equalToConstant: 72),
            closeBtn.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    private func buildGameOver() {
        gameOverView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
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
        finalScoreLabel.tag = 99
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
            titleLabel.centerYAnchor.constraint(equalTo: gameOverView.centerYAnchor, constant: -35),
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
    }

    @objc private func handleTap() {
        if isGameOver {
            resetGame()
            return
        }
        if !isPlaying {
            isPlaying = true
        }
        birdVelocityY = flapForce
    }

    @objc private func closeGame() {
        dismiss(animated: true)
    }

    // MARK: - Game Loop
    private func resetGame() {
        birdY = 0
        birdVelocityY = 0
        birdRotation = 0
        score = 0
        spawnTimer = 0
        isGameOver = false
        isPlaying = false
        wingPhase = 0

        for p in pipeNodes {
            p.top.removeFromParentNode()
            p.bottom.removeFromParentNode()
        }
        pipeNodes.removeAll()

        birdNode.position = SCNVector3(-5, 0, 0)
        birdNode.eulerAngles = SCNVector3(0, 0, 0)
        birdBody.eulerAngles = SCNVector3(0, 0, 0)
        birdWingL.eulerAngles = SCNVector3(0, 0, 0)
        birdWingR.eulerAngles = SCNVector3(0, 0, 0)

        gameOverView.isHidden = true
        updateScoreLabels()
    }

    private func tick() {
        if isGameOver { return }
        let dt: Float = 1.0 / 60.0

        if isPlaying {
            birdVelocityY -= gravity * dt
            birdY += birdVelocityY * dt
            let targetRotation = min(max(birdVelocityY * 0.12, -0.7), 0.5)
            birdRotation += (targetRotation - birdRotation) * 0.25
            birdNode.position.y = birdY
            birdNode.eulerAngles.z = birdRotation

            // Wing flap
            wingPhase += dt * 13
            let wingAngle = sin(wingPhase) * 0.45
            birdWingL.eulerAngles.x = wingAngle
            birdWingR.eulerAngles.x = -wingAngle

            // Spawn pipes
            spawnTimer += dt
            if spawnTimer >= spawnInterval {
                spawnPipe()
                spawnTimer = 0
            }

            // Move pipes & collision
            let birdHalf: Float = 0.35
            for i in (0..<pipeNodes.count).reversed() {
                let p = pipeNodes[i]
                p.top.position.x -= pipeSpeed * dt
                p.bottom.position.x -= pipeSpeed * dt

                if !p.passed && p.top.position.x + pipeWidth / 2 < birdNode.position.x {
                    pipeNodes[i].passed = true
                    score += 1
                    updateScoreLabels()
                }

                // Collision
                let px = p.top.position.x
                if abs(birdNode.position.x - px) < birdHalf + pipeWidth / 2 {
                    let topBot = p.top.position.y - Float(p.top.geometry?.boundingBox.max.y ?? 0)
                    let botTop = p.bottom.position.y + Float(p.bottom.geometry?.boundingBox.max.y ?? 0)
                    if birdY - birdHalf < topBot || birdY + birdHalf > botTop {
                        endGame()
                        return
                    }
                }

                if p.top.position.x < -worldHalfW - 2 {
                    p.top.removeFromParentNode()
                    p.bottom.removeFromParentNode()
                    pipeNodes.remove(at: i)
                }
            }

            // Ground/Ceiling
            if birdY - birdHalf < -worldHalfH || birdY + birdHalf > worldHalfH {
                endGame()
            }
        } else {
            // Idle float
            wingPhase += dt * 3
            birdNode.position.y = sin(wingPhase) * 0.35
        }
    }

    private func endGame() {
        isGameOver = true
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: "flappyBirdBest")
        }
        if let label = gameOverView.viewWithTag(99) as? UILabel {
            label.text = "得分: \(score)  最高: \(bestScore)"
        }
        gameOverView.isHidden = false
    }

    private func updateScoreLabels() {
        scoreLabel.text = "\(score)"
        bestLabel.text = "最高: \(bestScore)"
    }
}
