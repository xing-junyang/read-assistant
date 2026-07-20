import UIKit
import SceneKit

// MARK: - Subway Surfer View Controller
/// Minecraft-style 3D subway surfer game using SceneKit (iOS 10+).
/// Portrait-only, infinite track with Creeper chasing. Costs 30 coins per play.
final class SubwaySurferViewController: UIViewController {

    // MARK: - Constants
    private let lanePositions: [Float] = [-2.0, 0.0, 2.0]  // Left, Center, Right
    private let segmentLength: Float = 12.0
    private let visibleSegments = 8
    private let trackWidth: Float = 6.0
    private let playerHeight: Float = 1.0
    private let initialSpeed: Float = 8.0
    private let maxSpeed: Float = 35.0
    private let speedPerMeter: Float = 0.025  // Speed increases 0.025 per meter run
    private let coinRewardAmount = 5

    // MARK: - Game State
    private var currentLane = 1  // Start in center lane
    private var targetLane = 1
    private var isJumping = false
    private var jumpProgress: Float = 0
    private var isRolling = false
    private var rollProgress: Float = 0
    private var currentSpeed: Float = 8.0
    private var distance: Float = 0
    private var score: Int = 0
    private var collectedCoins: Int = 0
    private var isGameOver = false
    private var isTransitioning = false
    private var laneChangeDuration: Float = 0
    private var isPaused = false

    // Power-up state
    private var hasShield = false
    private var shieldNode: SCNNode?
    private var isFlying = false
    private var flyTimer: Float = 0
    private var hasBounceShoes = false
    private var bounceTimer: Float = 0

    // MARK: - SceneKit
    private let scnView = SCNView()
    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let playerNode = SCNNode()
    private let creeperNode = SCNNode()
    private var trackSegments: [[SCNNode]] = []  // [segmentIndex][nodes]
    private var obstacleNodes: [SCNNode] = []
    private var coinNodes: [SCNNode] = []
    private var powerUpNodes: [SCNNode] = []
    private var nextSegmentZ: Float = 0
    private var lastObstacleZ: Float = 20
    private var creeperBaseZ: Float = -3.0
    private var creeperBobPhase: Float = 0

    // MARK: - HUD
    private let scoreLabel = UILabel()
    private let coinLabel = UILabel()
    private let distanceLabel = UILabel()
    private let gameOverView = UIView()
    private let comboLabel = UILabel()
    private let powerUpIndicator = UILabel()
    private let pauseOverlay = UIView()

    // MARK: - Timer
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
        view.backgroundColor = UIColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1)
        buildScene()
        buildHUD()
        buildGameOver()
        setupGestures()
        spawnPlayer()
        spawnCreeper()
        generateInitialTrack()
        lastTime = CACurrentMediaTime()
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
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    // MARK: - SceneKit Setup
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

        // Camera - behind player, looking forward along the track (+Z)
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 200
        cameraNode.camera?.xFov = 50
        cameraNode.camera?.yFov = 50
        cameraNode.position = SCNVector3(0, 5.5, -6.5)
        cameraNode.eulerAngles = SCNVector3(-0.4, Float.pi, 0)
        scene.rootNode.addChildNode(cameraNode)

        // Lighting
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.6, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1)
        sun.position = SCNVector3(15, 30, 20)
        sun.constraints = [SCNLookAtConstraint(target: scene.rootNode)]
        scene.rootNode.addChildNode(sun)

        // Fog for depth
        scene.fogColor = UIColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1)
        scene.fogStartDistance = 35
        scene.fogEndDistance = 80

        // Ground plane
        let groundGeo = SCNFloor()
        groundGeo.reflectivity = 0
        groundGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.35, green: 0.65, blue: 0.25, alpha: 1)
        let ground = SCNNode(geometry: groundGeo)
        ground.position = SCNVector3(0, -0.6, 0)
        scene.rootNode.addChildNode(ground)
    }

    // MARK: - Player (Minecraft Steve Style)
    private func spawnPlayer() {
        // Body
        let bodyGeo = SCNBox(width: 0.6, height: 0.75, length: 0.35, chamferRadius: 0.02)
        bodyGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1) // Cyan shirt
        let body = SCNNode(geometry: bodyGeo)
        body.position.y = 0.85
        playerNode.addChildNode(body)

        // Head
        let headGeo = SCNBox(width: 0.5, height: 0.5, length: 0.5, chamferRadius: 0.02)
        headGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.85, green: 0.7, blue: 0.55, alpha: 1) // Skin tone
        let head = SCNNode(geometry: headGeo)
        head.position.y = 1.55
        head.name = "playerHead"
        playerNode.addChildNode(head)

        // Eyes
        let eyeGeo = SCNBox(width: 0.08, height: 0.08, length: 0.02, chamferRadius: 0)
        eyeGeo.firstMaterial?.diffuse.contents = UIColor.black
        let leftEye = SCNNode(geometry: eyeGeo)
        leftEye.position = SCNVector3(-0.12, 1.62, 0.26)
        playerNode.addChildNode(leftEye)
        let rightEye = SCNNode(geometry: eyeGeo)
        rightEye.position = SCNVector3(0.12, 1.62, 0.26)
        playerNode.addChildNode(rightEye)

        // Hair (dark brown)
        let hairGeo = SCNBox(width: 0.52, height: 0.15, length: 0.52, chamferRadius: 0.02)
        hairGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.15, blue: 0.05, alpha: 1)
        let hair = SCNNode(geometry: hairGeo)
        hair.position.y = 1.82
        playerNode.addChildNode(hair)

        // Legs
        let legGeo = SCNBox(width: 0.18, height: 0.6, length: 0.18, chamferRadius: 0.01)
        legGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1) // Dark blue pants
        let leftLeg = SCNNode(geometry: legGeo)
        leftLeg.position = SCNVector3(-0.14, 0.3, 0)
        leftLeg.name = "leftLeg"
        playerNode.addChildNode(leftLeg)
        let rightLeg = SCNNode(geometry: legGeo)
        rightLeg.position = SCNVector3(0.14, 0.3, 0)
        rightLeg.name = "rightLeg"
        playerNode.addChildNode(rightLeg)

        // Arms
        let armGeo = SCNBox(width: 0.16, height: 0.55, length: 0.16, chamferRadius: 0.01)
        armGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1)
        let leftArm = SCNNode(geometry: armGeo)
        leftArm.position = SCNVector3(-0.38, 1.0, 0)
        leftArm.name = "leftArm"
        playerNode.addChildNode(leftArm)
        let rightArm = SCNNode(geometry: armGeo)
        rightArm.position = SCNVector3(0.38, 1.0, 0)
        rightArm.name = "rightArm"
        playerNode.addChildNode(rightArm)

        playerNode.position = SCNVector3(lanePositions[currentLane], playerHeight, 0)
        scene.rootNode.addChildNode(playerNode)
    }

    // MARK: - Creeper
    private func spawnCreeper() {
        // Body
        let bodyGeo = SCNBox(width: 0.65, height: 0.8, length: 0.4, chamferRadius: 0.02)
        bodyGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.75, blue: 0.3, alpha: 1) // Creeper green
        let body = SCNNode(geometry: bodyGeo)
        body.position.y = 0.5
        creeperNode.addChildNode(body)

        // Creeper pixelated pattern on body
        let bodyFrontGeo = SCNBox(width: 0.35, height: 0.4, length: 0.01, chamferRadius: 0)
        bodyFrontGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1)
        let bodyFront = SCNNode(geometry: bodyFrontGeo)
        bodyFront.position = SCNVector3(0, 0.5, 0.21)
        creeperNode.addChildNode(bodyFront)

        // Head (larger cube)
        let headGeo = SCNBox(width: 0.55, height: 0.55, length: 0.55, chamferRadius: 0.02)
        headGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.75, blue: 0.3, alpha: 1)
        let head = SCNNode(geometry: headGeo)
        head.position.y = 1.08
        creeperNode.addChildNode(head)

        // Creeper face - eyes
        let eyeGeo = SCNBox(width: 0.14, height: 0.14, length: 0.02, chamferRadius: 0)
        eyeGeo.firstMaterial?.diffuse.contents = UIColor.black
        let leftEye = SCNNode(geometry: eyeGeo)
        leftEye.position = SCNVector3(-0.13, 1.22, 0.28)
        creeperNode.addChildNode(leftEye)
        let rightEye = SCNNode(geometry: eyeGeo)
        rightEye.position = SCNVector3(0.13, 1.22, 0.28)
        creeperNode.addChildNode(rightEye)

        // Creeper mouth
        let mouthGeo = SCNBox(width: 0.3, height: 0.18, length: 0.02, chamferRadius: 0)
        mouthGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
        let mouth = SCNNode(geometry: mouthGeo)
        mouth.position = SCNVector3(0, 1.0, 0.28)
        creeperNode.addChildNode(mouth)

        // Mouth detail lines
        for i in -1...1 {
            let lineGeo = SCNBox(width: 0.02, height: 0.16, length: 0.02, chamferRadius: 0)
            lineGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.75, blue: 0.3, alpha: 1)
            let line = SCNNode(geometry: lineGeo)
            line.position = SCNVector3(Float(i) * 0.1, 1.0, 0.29)
            creeperNode.addChildNode(line)
        }

        // Feet
        let footGeo = SCNBox(width: 0.25, height: 0.3, length: 0.25, chamferRadius: 0.01)
        footGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.2, green: 0.55, blue: 0.2, alpha: 1)
        let leftFoot = SCNNode(geometry: footGeo)
        leftFoot.position = SCNVector3(-0.18, 0.15, 0)
        leftFoot.name = "leftFoot"
        creeperNode.addChildNode(leftFoot)
        let rightFoot = SCNNode(geometry: footGeo)
        rightFoot.position = SCNVector3(0.18, 0.15, 0)
        rightFoot.name = "rightFoot"
        creeperNode.addChildNode(rightFoot)

        creeperBaseZ = -3.0
        creeperNode.position = SCNVector3(0, playerHeight, creeperBaseZ)
        creeperNode.eulerAngles.y = Float.pi  // Face toward player (+Z direction)
        scene.rootNode.addChildNode(creeperNode)
    }

    // MARK: - Track Generation
    private func generateTrackSegment(at baseZ: Float) -> [SCNNode] {
        var nodes: [SCNNode] = []

        // Road surface
        let halfSeg = segmentLength / 2
        let roadGeo = SCNBox(width: CGFloat(trackWidth), height: 0.15, length: CGFloat(segmentLength), chamferRadius: 0)
        roadGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1) // Gray road
        let road = SCNNode(geometry: roadGeo)
        road.position = SCNVector3(0, 0.08, baseZ + halfSeg)
        scene.rootNode.addChildNode(road)
        nodes.append(road)

        // Lane divider lines
        for laneIdx in 1..<lanePositions.count {
            let lineGeo = SCNBox(width: 0.08, height: 0.02, length: CGFloat(segmentLength) * 0.7, chamferRadius: 0)
            lineGeo.firstMaterial?.diffuse.contents = UIColor.white
            let line = SCNNode(geometry: lineGeo)
            let x = (lanePositions[laneIdx-1] + lanePositions[laneIdx]) / 2
            line.position = SCNVector3(x, 0.17, baseZ + halfSeg)
            scene.rootNode.addChildNode(line)
            nodes.append(line)
        }

        // Side rails (Minecraft-style fences/blocks)
        for side in [-1, 1] {
            let x = Float(side) * (trackWidth / 2 + 0.3)
            // Fence posts every 2 units
            for zOff in stride(from: Float(0), to: segmentLength, by: 2.0) {
                let postGeo = SCNBox(width: 0.2, height: 0.8, length: 0.2, chamferRadius: 0.02)
                postGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.55, green: 0.35, blue: 0.15, alpha: 1) // Wood
                let post = SCNNode(geometry: postGeo)
                post.position = SCNVector3(x, 0.45, baseZ + zOff + 1)
                scene.rootNode.addChildNode(post)
                nodes.append(post)
            }
            // Top rail
            let railGeo = SCNBox(width: 0.15, height: 0.1, length: CGFloat(segmentLength), chamferRadius: 0.01)
            railGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1)
            let rail = SCNNode(geometry: railGeo)
            rail.position = SCNVector3(x, 0.85, baseZ + halfSeg)
            scene.rootNode.addChildNode(rail)
            nodes.append(rail)
        }

        return nodes
    }

    private func generateInitialTrack() {
        nextSegmentZ = 0
        for _ in 0..<visibleSegments + 2 {
            let nodes = generateTrackSegment(at: nextSegmentZ)
            trackSegments.append(nodes)
            nextSegmentZ += segmentLength
        }
    }

    private func recycleTrack() {
        if let oldest = trackSegments.first {
            for node in oldest { node.removeFromParentNode() }
            trackSegments.removeFirst()
        }
        let nodes = generateTrackSegment(at: nextSegmentZ)
        trackSegments.append(nodes)
        nextSegmentZ += segmentLength
    }

    /// Ensure track exists up to at least the given Z position.
    private func ensureTrackExists(upTo z: Float) {
        while nextSegmentZ < z {
            let nodes = generateTrackSegment(at: nextSegmentZ)
            trackSegments.append(nodes)
            nextSegmentZ += segmentLength
        }
    }

    // MARK: - Obstacles
    private func spawnObstacleIfNeeded() {
        let minGap: Float = max(3.0, currentSpeed * 0.83)
        let playerZ = playerNode.presentation.position.z

        let spawnZ = max(lastObstacleZ + minGap, playerZ + 8.0)

        // Ensure track exists far enough ahead
        ensureTrackExists(upTo: spawnZ + 20)

        let z = spawnZ + Float.random(in: 0...4)

        // Pick 1-2 lanes
        let obstacleLane = Int.random(in: 0..<lanePositions.count)
        let secondLane = (obstacleLane + Int.random(in: 1...2)) % lanePositions.count

        // Weighted random obstacle type
        let obsType: Int = {
            let r = Float.random(in: 0...1)
            switch r {
            case 0.00..<0.05: return 0  // Stone block
            case 0.05..<0.10: return 1  // Stacked blocks
            case 0.10..<0.15: return 2  // Low barrier
            case 0.15..<0.20: return 3  // Tall fence
            case 0.20..<0.40: return 4  // Minecart
            case 0.40..<0.60: return 5  // Minecart
            case 0.60..<0.70: return 6  // Triple stack
            case 0.70..<0.80: return 7  // Train car (single)
            default:          return 8  // Train car sequence
            }
        }()

        if obsType == 8 {
            spawnTrainCarSequence(at: z)
            lastObstacleZ = z + 10  // Skip ahead for sequence
            return
        }

        spawnSingleObstacle(type: obsType, lane: obstacleLane, z: z)

        if Float.random(in: 0...1) < 0.65 {
            let type2: Int = {
                let r = Float.random(in: 0...1)
                switch r {
                case 0.00..<0.05: return 0
                case 0.05..<0.10: return 1
                case 0.10..<0.15: return 2
                case 0.15..<0.20: return 3
                case 0.20..<0.45: return 4
                case 0.45..<0.70: return 5
                case 0.70..<0.85: return 6
                default:          return 7
                }
            }()
            spawnSingleObstacle(type: type2, lane: secondLane, z: z + Float.random(in: -1...2))
        }

        lastObstacleZ = z
    }

    /// Spawn a sequence of 3-5 train cars that span the full track.
    /// Players can jump on top and run across the roofs.
    private func spawnTrainCarSequence(at baseZ: Float) {
        let carCount = Int.random(in: 3...5)
        let carLength: Float = 2.2
        let carGap: Float = 0.5
        let carHeight: Float = 0.9

        // 50% full-width, 50% per-lane with alternating lanes
        let isFullWidth = Float.random(in: 0...1) < 0.5
        let carWidth: Float = isFullWidth ? (trackWidth - 0.4) : 1.6
        let baseLaneIdx = Int.random(in: 0..<lanePositions.count)
        let baseLaneX: Float = isFullWidth ? 0 : lanePositions[baseLaneIdx]
        let alternateLanes = !isFullWidth && Float.random(in: 0...1) < 0.5

        for i in 0..<carCount {
            let car = SCNNode()

            // Car body - wide and flat-topped
            let bodyGeo = SCNBox(width: CGFloat(carWidth), height: CGFloat(carHeight), length: CGFloat(carLength), chamferRadius: 0.04)
            bodyGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 1) // Dark metal
            let body = SCNNode(geometry: bodyGeo)
            body.position.y = carHeight / 2
            car.addChildNode(body)

            // Roof highlight (lighter strip)
            let roofGeo = SCNBox(width: CGFloat(carWidth) - 0.3, height: 0.04, length: CGFloat(carLength) - 0.2, chamferRadius: 0)
            roofGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.4, green: 0.4, blue: 0.45, alpha: 1)
            let roof = SCNNode(geometry: roofGeo)
            roof.position.y = carHeight + 0.02
            car.addChildNode(roof)

            // Wheels
            for side in [-1, 1] {
                for wOff in [-1, 1] {
                    let wheelGeo = SCNCylinder(radius: 0.18, height: 0.1)
                    wheelGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
                    let wheel = SCNNode(geometry: wheelGeo)
                    wheel.eulerAngles = SCNVector3(0, 0, Float.pi/2)
                    wheel.position = SCNVector3(Float(side) * (carWidth/2 + 0.05), 0.15, Float(wOff) * (carLength/2 - 0.3))
                    car.addChildNode(wheel)
                }
            }

            let z = baseZ + Float(i) * (carLength + carGap)
            let carX: Float = alternateLanes ? ((i % 2 == 0) ? baseLaneX : lanePositions[(baseLaneIdx + 1) % lanePositions.count]) : baseLaneX
            car.position = SCNVector3(carX, 0.1, z)
            car.name = isFullWidth ? "traincar" : "traincar_lane"
            scene.rootNode.addChildNode(car)
            obstacleNodes.append(car)

            // Spawn coins on top of some cars
            if i % 2 == 0 && coinNodes.count < 25 {
                for c in 0..<3 {
                    let coin = makeCoin()
                    coin.position = SCNVector3(carX, carHeight + 0.35, z + Float(c) * 0.5 - 0.5)
                    scene.rootNode.addChildNode(coin)
                    coinNodes.append(coin)
                }
            }
        }
    }

    private func spawnSingleObstacle(type: Int, lane: Int, z: Float) {
        let obstacle = SCNNode()
        let x = lanePositions[lane]

        switch type {
        case 0:
            // Stone block
            let geo = SCNBox(width: 1.0, height: 1.0, length: 0.8, chamferRadius: 0.03)
            geo.firstMaterial?.diffuse.contents = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            let block = SCNNode(geometry: geo)
            block.position.y = 0.55
            obstacle.addChildNode(block)

        case 1:
            // Two stacked blocks
            for h in 0..<2 {
                let geo = SCNBox(width: 0.7, height: 0.7, length: 0.7, chamferRadius: 0.02)
                geo.firstMaterial?.diffuse.contents = UIColor(red: 0.7, green: 0.3, blue: 0.2, alpha: 1)
                let block = SCNNode(geometry: geo)
                block.position.y = 0.4 + Float(h) * 0.7
                obstacle.addChildNode(block)
            }

        case 2:
            // Low barrier (slide under)
            let geo = SCNBox(width: 2.0, height: 0.45, length: 0.3, chamferRadius: 0.02)
            geo.firstMaterial?.diffuse.contents = UIColor(red: 0.9, green: 0.75, blue: 0.2, alpha: 1)
            let bar = SCNNode(geometry: geo)
            bar.position.y = 0.28
            obstacle.addChildNode(bar)

        case 3:
            // Tall fence (lane-switch only)
            let postGeo = SCNBox(width: 0.2, height: 1.5, length: 0.15, chamferRadius: 0.01)
            postGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.6, green: 0.35, blue: 0.15, alpha: 1)
            let post1 = SCNNode(geometry: postGeo)
            post1.position = SCNVector3(-0.3, 0.8, 0); obstacle.addChildNode(post1)
            let post2 = SCNNode(geometry: SCNBox(width: 0.2, height: 1.5, length: 0.15, chamferRadius: 0.01))
            post2.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.6, green: 0.35, blue: 0.15, alpha: 1)
            post2.position = SCNVector3(0.3, 0.8, 0); obstacle.addChildNode(post2)
            let topGeo = SCNBox(width: 0.8, height: 0.12, length: 0.12, chamferRadius: 0.01)
            topGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.6, green: 0.35, blue: 0.15, alpha: 1)
            let top = SCNNode(geometry: topGeo)
            top.position.y = 1.55; obstacle.addChildNode(top)

        case 4, 5:
            // Minecraft minecart!
            let cartBodyGeo = SCNBox(width: 1.0, height: 0.4, length: 1.2, chamferRadius: 0.05)
            cartBodyGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.55, green: 0.35, blue: 0.15, alpha: 1) // Wood
            let cartBody = SCNNode(geometry: cartBodyGeo)
            cartBody.position.y = 0.35
            obstacle.addChildNode(cartBody)

            // Cart rim
            let rimGeo = SCNBox(width: 1.1, height: 0.08, length: 1.3, chamferRadius: 0.02)
            rimGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.4, green: 0.25, blue: 0.1, alpha: 1)
            let rim = SCNNode(geometry: rimGeo)
            rim.position.y = 0.55
            obstacle.addChildNode(rim)

            // Wheels (cylinders - like minecart wheels)
            for side in [-1, 1] {
                let wheelGeo = SCNCylinder(radius: 0.15, height: 0.12)
                wheelGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
                let wheel = SCNNode(geometry: wheelGeo)
                wheel.eulerAngles = SCNVector3(0, 0, Float.pi/2)
                wheel.position = SCNVector3(Float(side) * 0.5, 0.15, -0.35)
                obstacle.addChildNode(wheel)
                let wheel2 = SCNNode(geometry: SCNCylinder(radius: 0.15, height: 0.12))
                wheel2.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
                wheel2.eulerAngles = SCNVector3(0, 0, Float.pi/2)
                wheel2.position = SCNVector3(Float(side) * 0.5, 0.15, 0.35)
                obstacle.addChildNode(wheel2)
            }

        case 6:
            // Triple stacked blocks (hard!)
            for h in 0..<3 {
                let geo = SCNBox(width: 0.8, height: 0.65, length: 0.65, chamferRadius: 0.02)
                let colors: [UIColor] = [
                    UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1),
                    UIColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1),
                    UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
                ]
                geo.firstMaterial?.diffuse.contents = colors[h]
                let block = SCNNode(geometry: geo)
                block.position.y = 0.35 + Float(h) * 0.65
                obstacle.addChildNode(block)
            }

        case 7:
            // Single train car (per-lane width, you can jump on top!)
            let carW: Float = 1.6
            let carH: Float = 0.9
            let carL: Float = 2.2
            let bodyGeo = SCNBox(width: CGFloat(carW), height: CGFloat(carH), length: CGFloat(carL), chamferRadius: 0.04)
            bodyGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 1)
            let body = SCNNode(geometry: bodyGeo)
            body.position.y = carH / 2
            obstacle.addChildNode(body)

            let roofGeo = SCNBox(width: CGFloat(carW) - 0.3, height: 0.04, length: CGFloat(carL) - 0.2, chamferRadius: 0)
            roofGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.4, green: 0.4, blue: 0.45, alpha: 1)
            let roof = SCNNode(geometry: roofGeo)
            roof.position.y = carH + 0.02
            obstacle.addChildNode(roof)

            for side in [-1, 1] {
                for wOff in [-1, 1] {
                    let wheelGeo = SCNCylinder(radius: 0.18, height: 0.1)
                    wheelGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
                    let wheel = SCNNode(geometry: wheelGeo)
                    wheel.eulerAngles = SCNVector3(0, 0, Float.pi/2)
                    wheel.position = SCNVector3(Float(side) * (carW/2 + 0.05), 0.15, Float(wOff) * (carL/2 - 0.3))
                    obstacle.addChildNode(wheel)
                }
            }
            obstacle.name = "traincar"
        default: break
        }

        obstacle.position = SCNVector3(x, 0.1, z)
        scene.rootNode.addChildNode(obstacle)
        obstacleNodes.append(obstacle)
    }

    // MARK: - Coins
    private func spawnCoinsIfNeeded() {
        guard coinNodes.count < 25 else { return }

        let z = nextSegmentZ + Float.random(in: 4...12)
        let coinLane = Int.random(in: 0..<lanePositions.count)
        let x = lanePositions[coinLane]

        let count = Int.random(in: 3...5)
        for i in 0..<count {
            let coin = makeCoin()
            coin.position = SCNVector3(x, 1.2 + Float(i) * 0.05, z + Float(i) * 0.6)
            scene.rootNode.addChildNode(coin)
            coinNodes.append(coin)
        }
    }

    private func makeCoin() -> SCNNode {
        let coinNode = SCNNode()
        let coinGeo = SCNCylinder(radius: 0.22, height: 0.06)
        coinGeo.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.84, blue: 0, alpha: 1)
        coinGeo.firstMaterial?.specular.contents = UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)
        let coin = SCNNode(geometry: coinGeo)
        coinNode.addChildNode(coin)
        let innerGeo = SCNCylinder(radius: 0.08, height: 0.07)
        innerGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.9, green: 0.7, blue: 0, alpha: 1)
        let inner = SCNNode(geometry: innerGeo)
        coinNode.addChildNode(inner)
        coinNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        return coinNode
    }

    // MARK: - Power-ups
    private func spawnPowerUpIfNeeded() {
        guard powerUpNodes.count < 3 else { return }

        // Spawn roughly every 150-250 units
        if Int(distance) % 200 > 190 || powerUpNodes.isEmpty {
            // Don't spawn too close to each other
            if let last = powerUpNodes.last, last.position.z > nextSegmentZ - 15 { return }
        } else {
            return
        }

        let z = nextSegmentZ + Float.random(in: 6...14)
        let lane = Int.random(in: 0..<lanePositions.count)
        let x = lanePositions[lane]
        let powerType = Int.random(in: 0..<3)

        let pu = makePowerUp(type: powerType)
        pu.position = SCNVector3(x, 1.4, z)
        pu.name = "powerup_\(powerType)"
        scene.rootNode.addChildNode(pu)
        powerUpNodes.append(pu)
    }

    private func makePowerUp(type: Int) -> SCNNode {
        let node = SCNNode()

        switch type {
        case 0:
            // 🛡️ Shield - blue glowing cube
            let geo = SCNBox(width: 0.5, height: 0.5, length: 0.5, chamferRadius: 0.05)
            geo.firstMaterial?.diffuse.contents = UIColor(red: 0.2, green: 0.5, blue: 0.95, alpha: 1)
            geo.firstMaterial?.emission.contents = UIColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 1)
            let cube = SCNNode(geometry: geo)
            node.addChildNode(cube)

            // Diamond overlay
            let diamondGeo = SCNPyramid(width: 0.3, height: 0.2, length: 0.3)
            diamondGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.3, green: 0.7, blue: 1, alpha: 1)
            let diamond = SCNNode(geometry: diamondGeo)
            diamond.position.y = 0.35
            node.addChildNode(diamond)

        case 1:
            // 🦘 Bounce Shoes - orange spring
            let baseGeo = SCNBox(width: 0.4, height: 0.2, length: 0.4, chamferRadius: 0.03)
            baseGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.95, green: 0.55, blue: 0.1, alpha: 1)
            let base = SCNNode(geometry: baseGeo)
            node.addChildNode(base)

            // Spring coil
            let springGeo = SCNCylinder(radius: 0.15, height: 0.5)
            springGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
            let spring = SCNNode(geometry: springGeo)
            spring.position.y = 0.35
            node.addChildNode(spring)

        default:
            // 🕊️ Fly - white feather/elytra
            let wingGeo = SCNBox(width: 0.7, height: 0.08, length: 0.25, chamferRadius: 0.02)
            wingGeo.firstMaterial?.diffuse.contents = UIColor.white
            wingGeo.firstMaterial?.emission.contents = UIColor(white: 0.3, alpha: 1)
            let wing = SCNNode(geometry: wingGeo)
            wing.position.y = 0.1
            node.addChildNode(wing)

            let coreGeo = SCNBox(width: 0.2, height: 0.35, length: 0.2, chamferRadius: 0.03)
            coreGeo.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)
            let core = SCNNode(geometry: coreGeo)
            core.position.y = 0.25
            node.addChildNode(core)
        }

        // Floating ring effect
        let ringGeo = SCNTorus(ringRadius: 0.35, pipeRadius: 0.04)
        let ringColors: [UIColor] = [
            UIColor(red: 0.2, green: 0.5, blue: 0.95, alpha: 1),
            UIColor(red: 0.95, green: 0.55, blue: 0.1, alpha: 1),
            UIColor.white
        ]
        ringGeo.firstMaterial?.diffuse.contents = ringColors[type]
        ringGeo.firstMaterial?.emission.contents = ringColors[type].withAlphaComponent(0.4)
        let ring = SCNNode(geometry: ringGeo)
        ring.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        ring.name = "powerupRing"
        node.addChildNode(ring)

        return node
    }

    private func collectPowerUp(_ node: SCNNode) {
        guard let name = node.name, name.hasPrefix("powerup_") else { return }
        let typeStr = name.replacingOccurrences(of: "powerup_", with: "")
        guard let type = Int(typeStr) else { return }

        // Particle burst
        let colors: [UIColor] = [
            UIColor(red: 0.2, green: 0.5, blue: 0.95, alpha: 1),
            UIColor(red: 0.95, green: 0.55, blue: 0.1, alpha: 1),
            UIColor.white
        ]
        particlesBurst(at: node.presentation.position, color: colors[type], count: 15)

        switch type {
        case 0:
            activateShield()
            comboLabel.text = "🛡️ 护盾！"
            comboLabel.textColor = UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1)
        case 1:
            activateBounceShoes()
            comboLabel.text = "🦘 弹跳鞋！"
            comboLabel.textColor = UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)
        default:
            activateFlight()
            comboLabel.text = "🕊️ 飞行！"
            comboLabel.textColor = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        comboLabel.alpha = 1

        node.removeFromParentNode()
    }

    private func activateShield() {
        hasShield = true

        // Visual shield around player
        if shieldNode == nil {
            let sphereGeo = SCNSphere(radius: 0.85)
            sphereGeo.firstMaterial?.diffuse.contents = UIColor(red: 0.2, green: 0.5, blue: 0.95, alpha: 0.2)
            sphereGeo.firstMaterial?.emission.contents = UIColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 0.3)
            sphereGeo.firstMaterial?.transparency = 0.35
            shieldNode = SCNNode(geometry: sphereGeo)
            shieldNode!.position.y = 1.2
            playerNode.addChildNode(shieldNode!)
        }
        shieldNode?.isHidden = false
    }

    private func deactivateShield() {
        hasShield = false
        shieldNode?.isHidden = true
        comboLabel.text = "🛡️ 护盾消失"
        comboLabel.textColor = UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1)
        comboLabel.alpha = 1
    }

    private func activateBounceShoes() {
        hasBounceShoes = true
        bounceTimer = 8.0 // 8 seconds

        // Color player legs orange
        for child in playerNode.childNodes {
            if child.name == "leftLeg" || child.name == "rightLeg" {
                child.geometry?.firstMaterial?.emission.contents = UIColor(red: 0.95, green: 0.55, blue: 0.1, alpha: 1)
            }
        }
    }

    private func deactivateBounceShoes() {
        hasBounceShoes = false
        bounceTimer = 0
        for child in playerNode.childNodes {
            if child.name == "leftLeg" || child.name == "rightLeg" {
                child.geometry?.firstMaterial?.emission.contents = UIColor.clear
            }
        }
    }

    private func activateFlight() {
        isFlying = true
        flyTimer = 5.0 // 5 seconds

        // Visual: white wings on player
        for side in [-1, 1] {
            let wingGeo = SCNBox(width: 0.08, height: 0.3, length: 0.6, chamferRadius: 0.02)
            wingGeo.firstMaterial?.diffuse.contents = UIColor.white
            wingGeo.firstMaterial?.emission.contents = UIColor(white: 0.3, alpha: 1)
            let wing = SCNNode(geometry: wingGeo)
            wing.position = SCNVector3(Float(side) * 0.45, 1.1, 0)
            wing.eulerAngles.z = Float(side) * 0.4
            wing.name = "flyWing_\(side)"
            playerNode.addChildNode(wing)
        }
    }

    private func deactivateFlight() {
        isFlying = false
        flyTimer = 0
        for child in playerNode.childNodes {
            if child.name?.hasPrefix("flyWing_") == true {
                child.removeFromParentNode()
            }
        }
        playerNode.position.y = playerHeight
    }

    private func particlesBurst(at pos: SCNVector3, color: UIColor, count: Int) {
        for _ in 0..<count {
            let size = CGFloat.random(in: 0.04...0.12)
            let geo = SCNBox(width: size, height: size, length: size, chamferRadius: 0)
            geo.firstMaterial?.diffuse.contents = color
            let p = SCNNode(geometry: geo)
            p.position = pos
            scene.rootNode.addChildNode(p)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.6
            p.position = SCNVector3(pos.x + Float.random(in: -1.5...1.5),
                                     pos.y + Float.random(in: 1...4),
                                     pos.z + Float.random(in: -1.5...1.5))
            p.opacity = 0
            SCNTransaction.completionBlock = { p.removeFromParentNode() }
            SCNTransaction.commit()
        }
    }

    // MARK: - Gestures
    private func setupGestures() {
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
        swipeLeft.direction = .left
        view.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeRight)

        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
        swipeUp.direction = .up
        view.addGestureRecognizer(swipeUp)

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe))
        swipeDown.direction = .down
        view.addGestureRecognizer(swipeDown)
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard !isGameOver, !isTransitioning, !isPaused else { return }

        switch gesture.direction {
        case .left:
            if currentLane < lanePositions.count - 1 { targetLane = currentLane + 1; isTransitioning = true; laneChangeDuration = 0 }
        case .right:
            if currentLane > 0 { targetLane = currentLane - 1; isTransitioning = true; laneChangeDuration = 0 }
        case .up:
            if !isJumping && !isRolling { isJumping = true; jumpProgress = 0 }
        case .down:
            if !isJumping && !isRolling { isRolling = true; rollProgress = 0 }
        default:
            break
        }
    }

    // MARK: - HUD
    private func buildHUD() {
        // Top bar
        let topBar = UIView()
        topBar.backgroundColor = UIColor(white: 0, alpha: 0.4)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Pause button (left)
        let pauseBtn = UIButton(type: .system)
        pauseBtn.setTitle("⏸", for: .normal)
        pauseBtn.titleLabel?.font = .systemFont(ofSize: 22)
        pauseBtn.tintColor = .white
        pauseBtn.translatesAutoresizingMaskIntoConstraints = false
        pauseBtn.addTarget(self, action: #selector(pauseTap), for: .touchUpInside)
        topBar.addSubview(pauseBtn)

        // Exit button (right of pause)
        let exitBtn = UIButton(type: .system)
        exitBtn.setTitle("🚪", for: .normal)
        exitBtn.titleLabel?.font = .systemFont(ofSize: 20)
        exitBtn.tintColor = .white
        exitBtn.translatesAutoresizingMaskIntoConstraints = false
        exitBtn.addTarget(self, action: #selector(exitTap), for: .touchUpInside)
        topBar.addSubview(exitBtn)

        scoreLabel.text = "⭐ 0"
        scoreLabel.textColor = UIColor(red: 1, green: 0.85, blue: 0, alpha: 1)
        scoreLabel.font = .boldSystemFont(ofSize: 16)
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(scoreLabel)

        coinLabel.text = "🪙 0"
        coinLabel.textColor = UIColor(red: 1, green: 0.84, blue: 0, alpha: 1)
        coinLabel.font = .boldSystemFont(ofSize: 16)
        coinLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(coinLabel)

        distanceLabel.text = "📏 0m"
        distanceLabel.textColor = .white
        distanceLabel.font = .boldSystemFont(ofSize: 13)
        distanceLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(distanceLabel)

        NSLayoutConstraint.activate([
            pauseBtn.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            pauseBtn.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            pauseBtn.widthAnchor.constraint(equalToConstant: 40),

            exitBtn.leadingAnchor.constraint(equalTo: pauseBtn.trailingAnchor, constant: 2),
            exitBtn.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            exitBtn.widthAnchor.constraint(equalToConstant: 40),

            scoreLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor, constant: -50),
            scoreLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            coinLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor, constant: 50),
            coinLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            distanceLabel.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -14),
            distanceLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor)
        ])

        // Pause overlay
        pauseOverlay.backgroundColor = UIColor(white: 0, alpha: 0.7)
        pauseOverlay.alpha = 0
        pauseOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pauseOverlay)
        NSLayoutConstraint.activate([
            pauseOverlay.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            pauseOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pauseOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pauseOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let pauseTitle = UILabel()
        pauseTitle.text = "⏸ 游戏暂停"
        pauseTitle.textColor = .white
        pauseTitle.font = .boldSystemFont(ofSize: 36)
        pauseTitle.textAlignment = .center
        pauseTitle.translatesAutoresizingMaskIntoConstraints = false
        pauseOverlay.addSubview(pauseTitle)

        let resumeBtn = UIButton(type: .system)
        resumeBtn.setTitle("▶️ 继续游戏", for: .normal)
        resumeBtn.titleLabel?.font = .boldSystemFont(ofSize: 24)
        resumeBtn.setTitleColor(.white, for: .normal)
        resumeBtn.backgroundColor = UIColor(red: 0.2, green: 0.75, blue: 0.3, alpha: 1)
        resumeBtn.layer.cornerRadius = 14
        resumeBtn.translatesAutoresizingMaskIntoConstraints = false
        resumeBtn.addTarget(self, action: #selector(resumeTap), for: .touchUpInside)
        pauseOverlay.addSubview(resumeBtn)

        let quitBtn = UIButton(type: .system)
        quitBtn.setTitle("🚪 退出游戏", for: .normal)
        quitBtn.titleLabel?.font = .boldSystemFont(ofSize: 18)
        quitBtn.setTitleColor(UIColor(white: 0.8, alpha: 1), for: .normal)
        quitBtn.backgroundColor = UIColor(white: 0.25, alpha: 1)
        quitBtn.layer.cornerRadius = 12
        quitBtn.translatesAutoresizingMaskIntoConstraints = false
        quitBtn.addTarget(self, action: #selector(pauseExitTap), for: .touchUpInside)
        pauseOverlay.addSubview(quitBtn)

        NSLayoutConstraint.activate([
            pauseTitle.centerXAnchor.constraint(equalTo: pauseOverlay.centerXAnchor),
            pauseTitle.centerYAnchor.constraint(equalTo: pauseOverlay.centerYAnchor, constant: -50),

            resumeBtn.centerXAnchor.constraint(equalTo: pauseOverlay.centerXAnchor),
            resumeBtn.topAnchor.constraint(equalTo: pauseTitle.bottomAnchor, constant: 30),
            resumeBtn.widthAnchor.constraint(equalToConstant: 220),
            resumeBtn.heightAnchor.constraint(equalToConstant: 54),

            quitBtn.centerXAnchor.constraint(equalTo: pauseOverlay.centerXAnchor),
            quitBtn.topAnchor.constraint(equalTo: resumeBtn.bottomAnchor, constant: 14),
            quitBtn.widthAnchor.constraint(equalToConstant: 220),
            quitBtn.heightAnchor.constraint(equalToConstant: 46)
        ])

        // Combo label
        comboLabel.textColor = UIColor(red: 1, green: 0.9, blue: 0.3, alpha: 1)
        comboLabel.font = .boldSystemFont(ofSize: 28)
        comboLabel.textAlignment = .center
        comboLabel.alpha = 0
        comboLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(comboLabel)
        NSLayoutConstraint.activate([
            comboLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            comboLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -80)
        ])

        // Creeper warning
        let warningLabel = UILabel()
        warningLabel.text = "💥 苦力怕正在追你！快跑！"
        warningLabel.textColor = UIColor(red: 1, green: 0.4, blue: 0.4, alpha: 0.8)
        warningLabel.font = .boldSystemFont(ofSize: 12)
        warningLabel.textAlignment = .center
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(warningLabel)
        NSLayoutConstraint.activate([
            warningLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            warningLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])

        // Power-up indicator
        powerUpIndicator.textColor = .white
        powerUpIndicator.font = .boldSystemFont(ofSize: 13)
        powerUpIndicator.textAlignment = .center
        powerUpIndicator.alpha = 0
        powerUpIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(powerUpIndicator)
        NSLayoutConstraint.activate([
            powerUpIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            powerUpIndicator.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 6)
        ])
    }

    private func refreshHUD() {
        scoreLabel.text = "⭐ \(score)"
        coinLabel.text = "🪙 \(collectedCoins)"
        let kmh = Int(currentSpeed * 3.6)
        distanceLabel.text = "📏 \(Int(distance))m · \(kmh)km/h"
    }

    // MARK: - Game Over
    private func buildGameOver() {
        gameOverView.backgroundColor = UIColor(white: 0, alpha: 0.88)
        gameOverView.alpha = 0
        gameOverView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gameOverView)
        NSLayoutConstraint.activate([
            gameOverView.topAnchor.constraint(equalTo: view.topAnchor),
            gameOverView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gameOverView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gameOverView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let icon = UILabel()
        icon.text = "💥"
        icon.font = .systemFont(ofSize: 60)
        icon.textAlignment = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        gameOverView.addSubview(icon)

        let title = UILabel()
        title.text = "苦力怕追上你了！"
        title.textColor = UIColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
        title.font = .boldSystemFont(ofSize: 30)
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        gameOverView.addSubview(title)

        let stats = UILabel()
        stats.tag = 200
        stats.textColor = .white
        stats.font = .systemFont(ofSize: 18)
        stats.textAlignment = .center
        stats.numberOfLines = 0
        stats.translatesAutoresizingMaskIntoConstraints = false
        gameOverView.addSubview(stats)

        let coinReward = UILabel()
        coinReward.tag = 201
        coinReward.textColor = UIColor(red: 1, green: 0.84, blue: 0, alpha: 1)
        coinReward.font = .boldSystemFont(ofSize: 18)
        coinReward.textAlignment = .center
        coinReward.translatesAutoresizingMaskIntoConstraints = false
        gameOverView.addSubview(coinReward)

        let retryBtn = UIButton(type: .system)
        let cost = DeveloperSettingsManager.shared.effectiveSubwaySurferCostCoins
        retryBtn.setTitle("🔄 再来一局 (-\(cost)💰)", for: .normal)
        retryBtn.titleLabel?.font = .boldSystemFont(ofSize: 22)
        retryBtn.setTitleColor(.white, for: .normal)
        retryBtn.backgroundColor = UIColor(red: 0.2, green: 0.75, blue: 0.3, alpha: 1)
        retryBtn.layer.cornerRadius = 14
        retryBtn.translatesAutoresizingMaskIntoConstraints = false
        retryBtn.addTarget(self, action: #selector(retryTap), for: .touchUpInside)
        gameOverView.addSubview(retryBtn)

        let exitBtn = UIButton(type: .system)
        exitBtn.setTitle("🚪 退出", for: .normal)
        exitBtn.titleLabel?.font = .boldSystemFont(ofSize: 18)
        exitBtn.setTitleColor(UIColor(white: 0.8, alpha: 1), for: .normal)
        exitBtn.backgroundColor = UIColor(white: 0.25, alpha: 1)
        exitBtn.layer.cornerRadius = 12
        exitBtn.translatesAutoresizingMaskIntoConstraints = false
        exitBtn.addTarget(self, action: #selector(exitTap), for: .touchUpInside)
        gameOverView.addSubview(exitBtn)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            icon.bottomAnchor.constraint(equalTo: title.topAnchor, constant: -10),

            title.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            title.bottomAnchor.constraint(equalTo: gameOverView.centerYAnchor, constant: -40),

            stats.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            stats.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),

            coinReward.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            coinReward.topAnchor.constraint(equalTo: stats.bottomAnchor, constant: 12),

            retryBtn.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            retryBtn.topAnchor.constraint(equalTo: coinReward.bottomAnchor, constant: 24),
            retryBtn.widthAnchor.constraint(equalToConstant: 240),
            retryBtn.heightAnchor.constraint(equalToConstant: 54),

            exitBtn.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            exitBtn.topAnchor.constraint(equalTo: retryBtn.bottomAnchor, constant: 12),
            exitBtn.widthAnchor.constraint(equalToConstant: 240),
            exitBtn.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    private func endGame() {
        isGameOver = true

        // Clean up power-ups
        deactivateFlight()
        deactivateBounceShoes()
        hasShield = false

        // Creeper explodes
        explodeCreeper()

        // Reward coins based on collected coins
        let reward = max(1, collectedCoins / 3)
        RewardManager.shared.coins += reward

        (gameOverView.viewWithTag(200) as? UILabel)?.text = "🏃 跑了 \(Int(distance)) 米\n⭐ 得分: \(score)\n🪙 收集: \(collectedCoins) 金币"
        (gameOverView.viewWithTag(201) as? UILabel)?.text = "🎁 奖励: +\(reward) 金币"

        UIView.animate(withDuration: 0.5) { self.gameOverView.alpha = 1 }
    }

    private func explodeCreeper() {
        // Particle explosion effect
        let count = 30
        for _ in 0..<count {
            let size = CGFloat.random(in: 0.05...0.2)
            let geo = SCNBox(width: size, height: size, length: size, chamferRadius: 0)
            let colors: [UIColor] = [
                UIColor(red: 0.3, green: 0.75, blue: 0.3, alpha: 1),
                UIColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1),
                UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1),
                UIColor(red: 1, green: 1, blue: 0.3, alpha: 1),
            ]
            geo.firstMaterial?.diffuse.contents = colors.randomElement()!
            let particle = SCNNode(geometry: geo)
            particle.position = creeperNode.presentation.position
            scene.rootNode.addChildNode(particle)

            let dx = Float.random(in: -3...3)
            let dy = Float.random(in: 1...5)
            let dz = Float.random(in: -2...2)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.0
            particle.position = SCNVector3(particle.position.x + dx, particle.position.y + dy, particle.position.z + dz)
            particle.opacity = 0
            particle.scale = SCNVector3(0.1, 0.1, 0.1)
            SCNTransaction.completionBlock = { particle.removeFromParentNode() }
            SCNTransaction.commit()
        }

        // Flash view red
        UIView.animate(withDuration: 0.15, animations: {
            self.view.backgroundColor = UIColor(red: 1, green: 0.3, blue: 0.1, alpha: 1)
        }) { _ in
            UIView.animate(withDuration: 0.3) {
                self.view.backgroundColor = UIColor(red: 0.53, green: 0.81, blue: 0.92, alpha: 1)
            }
        }
    }

    @objc private func retryTap() {
        let cost = DeveloperSettingsManager.shared.effectiveSubwaySurferCostCoins
        guard RewardManager.shared.spendCoins(cost) else {
            let a = UIAlertController(title: "金币不足", message: "需要\(cost)金币才能玩，请先完成阅读获取金币。", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "返回", style: .default) { [weak self] _ in self?.dismiss(animated: true) })
            present(a, animated: true)
            return
        }
        resetGame()
        UIView.animate(withDuration: 0.3) { self.gameOverView.alpha = 0 }
    }

    @objc private func exitTap() { dismiss(animated: true) }

    @objc private func pauseTap() {
        guard !isGameOver else { return }
        isPaused = true
        lastTime = 0 // Force dt=0 on resume, preventing time jump
        UIView.animate(withDuration: 0.25) { self.pauseOverlay.alpha = 1 }
    }

    @objc private func resumeTap() {
        isPaused = false
        lastTime = CACurrentMediaTime()
        UIView.animate(withDuration: 0.25) { self.pauseOverlay.alpha = 0 }
    }

    @objc private func pauseExitTap() {
        dismiss(animated: true)
    }

    private func resetGame() {
        currentLane = 1; targetLane = 1
        isJumping = false; jumpProgress = 0
        isRolling = false; rollProgress = 0
        currentSpeed = initialSpeed
        distance = 0; score = 0; collectedCoins = 0
        isGameOver = false; isTransitioning = false
        laneChangeDuration = 0
        isPaused = false
        pauseOverlay.alpha = 0
        lastObstacleZ = 20

        // Reset power-ups
        hasShield = false; shieldNode?.isHidden = true
        deactivateFlight(); deactivateBounceShoes()

        // Clean up
        for n in obstacleNodes { n.removeFromParentNode() }; obstacleNodes.removeAll()
        for n in coinNodes { n.removeFromParentNode() }; coinNodes.removeAll()
        for n in powerUpNodes { n.removeFromParentNode() }; powerUpNodes.removeAll()
        for seg in trackSegments { for n in seg { n.removeFromParentNode() } }
        trackSegments.removeAll()

        // Reset player
        playerNode.position = SCNVector3(lanePositions[currentLane], playerHeight, 0)
        playerNode.eulerAngles = SCNVector3(0, 0, 0)
        for child in playerNode.childNodes {
            if child.name == "playerHead" { child.position.y = 1.55 }
            if child.name == "leftLeg" { child.position.y = 0.3; child.geometry?.firstMaterial?.emission.contents = UIColor.clear }
            if child.name == "rightLeg" { child.position.y = 0.3; child.geometry?.firstMaterial?.emission.contents = UIColor.clear }
            if child.name == "leftArm" { child.position.y = 1.0 }
            if child.name == "rightArm" { child.position.y = 1.0 }
        }

        // Reset creeper
        creeperBaseZ = -3.0
        creeperNode.position = SCNVector3(0, playerHeight, creeperBaseZ)
        creeperNode.isHidden = false

        generateInitialTrack()
        refreshHUD()
        lastTime = CACurrentMediaTime()
    }

    // MARK: - Game Loop
    private func tick() {
        guard !isGameOver else { return }
        guard !isPaused else { return }
        let now = CACurrentMediaTime()
        let dt = Float(min(now - lastTime, 0.1))
        lastTime = now

        // Speed increases with distance
        currentSpeed = min(maxSpeed, initialSpeed + distance * speedPerMeter)
        distance += currentSpeed * dt

        // Power-up timers
        if isFlying {
            flyTimer -= dt
            if flyTimer <= 0 { deactivateFlight() }
        }
        if hasBounceShoes {
            bounceTimer -= dt
            if bounceTimer <= 0 { deactivateBounceShoes() }
        }

        // Lane change animation
        if isTransitioning {
            laneChangeDuration += dt
            let t = min(laneChangeDuration / 0.15, 1.0)
            let fromX = lanePositions[currentLane]
            let toX = lanePositions[targetLane]
            let eased = t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
            playerNode.position.x = fromX + (toX - fromX) * eased
            if t >= 1.0 {
                currentLane = targetLane
                playerNode.position.x = toX
                isTransitioning = false
                laneChangeDuration = 0
            }
        }

        // Jump animation
        if isJumping {
            jumpProgress += dt
            let t = jumpProgress / 0.6
            if t <= 1.0 {
                let height = sin(t * Float.pi) * 2.2
                playerNode.position.y = playerHeight + height
                if let ll = playerNode.childNode(withName: "leftLeg", recursively: false) {
                    ll.position.y = 0.3 - height * 0.3
                }
                if let rl = playerNode.childNode(withName: "rightLeg", recursively: false) {
                    rl.position.y = 0.3 - height * 0.3
                }
            } else {
                // Auto-bounce if has bounce shoes
                if hasBounceShoes && !isFlying {
                    isJumping = true; jumpProgress = 0
                } else {
                    isJumping = false; jumpProgress = 0
                    playerNode.position.y = playerHeight
                    if let ll = playerNode.childNode(withName: "leftLeg", recursively: false) { ll.position.y = 0.3 }
                    if let rl = playerNode.childNode(withName: "rightLeg", recursively: false) { rl.position.y = 0.3 }
                }
            }
        }

        // Flying state
        if isFlying {
            playerNode.position.y = playerHeight + 2.5 + sin(Float(now) * 4) * 0.3
            // Flap wings
            for child in playerNode.childNodes {
                if child.name == "flyWing_1" {
                    child.eulerAngles.z = 0.4 + sin(Float(now) * 12) * 0.5
                } else if child.name == "flyWing_-1" {
                    child.eulerAngles.z = -0.4 + sin(Float(now) * 12 + Float.pi) * 0.5
                }
            }
        }

        // Roll animation
        if isRolling {
            rollProgress += dt
            let t = rollProgress / 0.5
            if t <= 1.0 {
                playerNode.eulerAngles.x = t * Float.pi * 2
                playerNode.position.y = playerHeight - 0.3
            } else {
                isRolling = false; rollProgress = 0
                playerNode.eulerAngles.x = 0
                playerNode.position.y = playerHeight
            }
        }

        // Running animation
        if !isJumping && !isRolling && !isFlying {
            let runFreq: Float = currentSpeed * 0.8
            let armSwing = sin(Float(now) * runFreq) * 0.4
            let legSwing = sin(Float(now) * runFreq) * 0.3
            if let la = playerNode.childNode(withName: "leftArm", recursively: false) { la.eulerAngles.x = armSwing }
            if let ra = playerNode.childNode(withName: "rightArm", recursively: false) { ra.eulerAngles.x = -armSwing }
            if let ll = playerNode.childNode(withName: "leftLeg", recursively: false) {
                ll.eulerAngles.x = -legSwing; ll.position.y = 0.3 + abs(legSwing) * 0.15
            }
            if let rl = playerNode.childNode(withName: "rightLeg", recursively: false) {
                rl.eulerAngles.x = legSwing; rl.position.y = 0.3 + abs(legSwing) * 0.15
            }
            if let h = playerNode.childNode(withName: "playerHead", recursively: false) {
                h.position.y = 1.55 + abs(sin(Float(now) * runFreq * 2)) * 0.05
            }
        }

        // Creeper chase
        creeperBobPhase += dt
        let creeperTargetZ = playerNode.position.z + creeperBaseZ
        creeperNode.position.z += (creeperTargetZ - creeperNode.position.z) * 0.1
        creeperNode.position.y = playerHeight + sin(creeperBobPhase * 6) * 0.08

        let chaseProgress = min(distance / 500.0, 1.0)
        creeperNode.position.z += chaseProgress * 3.0 * dt

        let creeperDist = playerNode.position.z - creeperNode.position.z
        if creeperDist < 1.5 && !isGameOver {
            if hasShield {
                deactivateShield()
                // Push creeper back
                creeperNode.position.z -= 10
            } else {
                endGame()
                return
            }
        }

        if creeperDist < 5 && creeperDist > 1.5 {
            let urgency = 1.0 - (creeperDist - 1.5) / 3.5
            comboLabel.text = "⚠️ 危险！\(String(format: "%.1f", creeperDist))m"
            comboLabel.textColor = UIColor(red: 1, green: CGFloat(1 - urgency * 0.7), blue: CGFloat(0.2 * (1 - urgency)), alpha: 1)
            comboLabel.alpha = CGFloat(0.3 + urgency * 0.7)
        } else if creeperDist >= 5 {
            comboLabel.alpha = max(0, comboLabel.alpha - CGFloat(dt) * 3)
        }

        // Track recycling
        if nextSegmentZ - playerNode.position.z < segmentLength * Float(visibleSegments) {
            recycleTrack()
        }

        // Spawn
        spawnObstacleIfNeeded()
        spawnCoinsIfNeeded()
        spawnPowerUpIfNeeded()

        // Move entities (toward player at z=0)
        moveAndCheckObstacles(dt)
        moveAndCheckCoins(dt)
        moveAndCheckPowerUps(dt)

        // Shield rotation
        if hasShield, let sn = shieldNode {
            sn.eulerAngles.y += dt * 2
        }

        score = Int(distance) + collectedCoins * 10
        refreshHUD()
        updatePowerUpIndicator()
    }

    private func updatePowerUpIndicator() {
        if hasShield {
            powerUpIndicator.text = "🛡️ 护盾"
            powerUpIndicator.textColor = UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1)
            powerUpIndicator.alpha = 1
        } else if isFlying {
            powerUpIndicator.text = String(format: "🕊️ 飞行 %.1fs", flyTimer)
            powerUpIndicator.textColor = .white
            powerUpIndicator.alpha = 1
        } else if hasBounceShoes {
            powerUpIndicator.text = String(format: "🦘 弹跳 %.1fs", bounceTimer)
            powerUpIndicator.textColor = UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)
            powerUpIndicator.alpha = 1
        } else {
            powerUpIndicator.alpha = max(0, powerUpIndicator.alpha - 0.05)
        }
    }

    private func moveAndCheckObstacles(_ dt: Float) {
        var toRemove: [Int] = []
        for i in 0..<obstacleNodes.count {
            let obs = obstacleNodes[i]
            obs.position.z -= currentSpeed * dt

            if obs.position.z < playerNode.position.z - 15 {
                toRemove.append(i)
                obs.removeFromParentNode()
                continue
            }

            let px = playerNode.presentation.position.x
            let py = playerNode.presentation.position.y
            let pz = playerNode.presentation.position.z

            let dx = abs(obs.position.x - px)
            let dz = abs(obs.position.z - pz)

            // Train cars: wider X range for full-width, can run on top
            let isTrainCar = obs.name == "traincar" || obs.name == "traincar_lane"
            let xThreshold: Float = (obs.name == "traincar") ? trackWidth / 2 : ((obs.name == "traincar_lane") ? 0.85 : 0.7)

            if dz < 0.65 && dx < xThreshold && obs.position.z > pz - 0.3 {
                if isFlying { continue }

                // Train cars: player can land on top
                if isTrainCar {
                    let carTop: Float = 1.05  // Roof height
                    if py > carTop {
                        // Running on top of train car
                        playerNode.position.y = carTop + 0.1
                        continue
                    }
                }

                if isJumping && py > playerHeight + 1.2 { continue }
                if isRolling && py < playerHeight - 0.1 { continue }

                if hasShield {
                    deactivateShield()
                    obs.removeFromParentNode()
                    toRemove.append(i)
                    particlesBurst(at: obs.position, color: UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 1), count: 10)
                    continue
                }

                endGame()
                return
            }
        }
        for idx in toRemove.sorted(by: >) { obstacleNodes.remove(at: idx) }
    }

    private func moveAndCheckCoins(_ dt: Float) {
        var toRemove: [Int] = []
        for i in 0..<coinNodes.count {
            let coin = coinNodes[i]
            coin.position.z -= currentSpeed * dt
            coin.eulerAngles.y += dt * 3

            if coin.position.z < playerNode.position.z - 8 {
                toRemove.append(i)
                coin.removeFromParentNode()
                continue
            }

            let px = playerNode.presentation.position.x
            let py = playerNode.presentation.position.y
            let pz = playerNode.presentation.position.z

            if abs(coin.position.x - px) < 0.8 && abs(coin.position.y - py) < 1.5 && abs(coin.position.z - pz) < 0.6 {
                toRemove.append(i)
                coin.removeFromParentNode()
                collectedCoins += 1

                let geo = SCNBox(width: 0.08, height: 0.08, length: 0.08, chamferRadius: 0)
                geo.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.84, blue: 0, alpha: 1)
                let p = SCNNode(geometry: geo)
                p.position = coin.position
                scene.rootNode.addChildNode(p)
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.5
                p.position.y += 2; p.opacity = 0
                SCNTransaction.completionBlock = { p.removeFromParentNode() }
                SCNTransaction.commit()

                comboLabel.text = "🪙 +1"
                comboLabel.textColor = UIColor(red: 1, green: 0.84, blue: 0, alpha: 1)
                comboLabel.alpha = 1
            }
        }
        for idx in toRemove.sorted(by: >) { coinNodes.remove(at: idx) }
    }

    private func moveAndCheckPowerUps(_ dt: Float) {
        var toRemove: [Int] = []
        for i in 0..<powerUpNodes.count {
            let pu = powerUpNodes[i]
            pu.position.z -= currentSpeed * dt

            // Rotate ring
            if let ring = pu.childNode(withName: "powerupRing", recursively: false) {
                ring.eulerAngles.z += dt * 3
            }
            // Bob up and down
            pu.position.y = Float(1.4 + sin(CACurrentMediaTime() * 3) * 0.2)

            if pu.position.z < playerNode.position.z - 8 {
                toRemove.append(i)
                pu.removeFromParentNode()
                continue
            }

            let px = playerNode.presentation.position.x
            let py = playerNode.presentation.position.y
            let pz = playerNode.presentation.position.z

            if abs(pu.position.x - px) < 0.8 && abs(pu.position.y - py) < 1.8 && abs(pu.position.z - pz) < 0.7 {
                toRemove.append(i)
                collectPowerUp(pu)
            }
        }
        for idx in toRemove.sorted(by: >) { powerUpNodes.remove(at: idx) }
    }
}
